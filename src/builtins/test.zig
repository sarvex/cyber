const std = @import("std");
const builtin = @import("builtin");
const stdx = @import("stdx");
const cy = @import("../cyber.zig");
const Value = cy.Value;
const vm_ = @import("../vm.zig");
const gvm = &vm_.gvm;
const fmt = @import("../fmt.zig");
const bindings = @import("bindings.zig");
const Symbol = bindings.Symbol;
const prepareThrowSymbol = bindings.prepareThrowSymbol;
const bt = cy.types.BuiltinTypeSymIds;
const v = fmt.v;

pub fn initModule(c: *cy.VMcompiler, modId: cy.ModuleId) linksection(cy.InitSection) !void {
    const b = bindings.ModuleBuilder.init(c, modId);

    try b.setFunc("eq", &.{bt.Any, bt.Any}, bt.Any, eq);
    try b.setFunc("eqList", &.{bt.Any, bt.Any}, bt.Any, eqList);
    try b.setFunc("eqNear", &.{bt.Any, bt.Any}, bt.Any, eqNear);
    if (builtin.is_test) {
        // Only available for zig test, until `any` local type specifier is implemented.
        try b.setFunc("erase", &.{bt.Any}, bt.Any, erase);
    }
    try b.setFunc("fail", &.{}, bt.Any, fail);
}

fn fail(vm: *cy.UserVM, _: [*]const Value, _: u8) Value {
    return prepareThrowSymbol(vm, .AssertError);
}

/// Simply returns the value so the caller get's an erased `any` type.
fn erase(_: *cy.UserVM, args: [*]const Value, _: u8) Value {
    return args[0];
}

fn getComparableTag(val: Value) cy.ValueUserTag {
    return val.getUserTag();
}

fn eq2(vm: *cy.UserVM, act: Value, exp: Value) linksection(cy.StdSection) bool {
    const actType = getComparableTag(act);
    const expType = getComparableTag(exp);
    if (actType == expType) {
        switch (actType) {
            .int => {
                if (act.asInteger() == exp.asInteger()) {
                    return true;
                } else {
                    printStderr("actual: {} != {}\n", &.{v(act.asInteger()), v(exp.asInteger())});
                    return false;
                }
            },
            .number => {
                if (act.asF64() == exp.asF64()) {
                    return true;
                } else {
                    printStderr("actual: {} != {}\n", &.{v(act.asF64()), v(exp.asF64())});
                    return false;
                }
            },
            .string => {
                const actStr = vm.valueAsString(act);
                const expStr = vm.valueAsString(exp);
                if (std.mem.eql(u8, actStr, expStr)) {
                    return true;
                } else {
                    printStderr("actual: '{}' != '{}'\n", &.{v(actStr), v(expStr)});
                    return false;
                }
            },
            .rawstring => {
                const actStr = act.asRawString();
                const expStr = exp.asRawString();
                if (std.mem.eql(u8, actStr, expStr)) {
                    return true;
                } else {
                    printStderr("actual: '{}' != '{}'\n", &.{v(actStr), v(expStr)});
                    return false;
                }
            },
            .pointer => {
                const actPtr = act.asPointer(*cy.Pointer).ptr;
                const expPtr = exp.asPointer(*cy.Pointer).ptr;
                if (actPtr == expPtr) {
                    return true;
                } else {
                    printStderr("actual: {} != {}\n", &.{v(actPtr), v(expPtr)});
                    return false;
                }
            },
            .boolean => {
                const actv = act.asBool();
                const expv = exp.asBool();
                if (actv == expv) {
                    return true;
                } else {
                    printStderr("actual: {} != {}\n", &.{v(actv), v(expv)});
                    return false;
                }
            },
            .symbol => {
                const actv = act.asSymbolId();
                const expv = exp.asSymbolId();
                if (actv == expv) {
                    return true;
                } else {
                    printStderr("actual: {} != {}\n", &.{v(gvm.syms.buf[actv].name), v(gvm.syms.buf[expv].name)});
                    return false;
                }
            },
            .none => {
                return true;
            },
            .err => {
                const actv = act.asErrorSymbol();
                const expv = exp.asErrorSymbol();
                if (actv == expv) {
                    return true;
                } else {
                    const ivm = vm.internal();
                    const actName: []const u8 = if (act.isInterrupt()) "Interrupt" else ivm.syms.buf[actv].name;
                    const expName: []const u8 = if (exp.isInterrupt()) "Interrupt" else ivm.syms.buf[expv].name;
                    printStderr("actual: error.{} != error.{}\n", &.{v(actName), v(expName)});
                    return false;
                }
            },
            .map,
            .list,
            .object => {
                const actv = act.asAnyOpaque();
                const expv = exp.asAnyOpaque();
                if (actv == expv) {
                    return true;
                } else {
                    printStderr("actual: {} != {}\n", &.{v(actv), v(expv)});
                    return false;
                }
            },
            .metatype => {
                const actv = act.asHeapObject().metatype;
                const expv = exp.asHeapObject().metatype;
                if (std.meta.eql(actv, expv)) {
                    return true;
                } else {
                    printStderr("actual: {} != {}\n", &.{v(actv.symId), v(expv.symId)});
                    return false;
                }
            },
            else => {
                stdx.panicFmt("Unsupported type {}", .{actType});
            }
        }
    } else {
        printStderr("Types do not match:\n", &.{});
        printStderr("actual: {} != {}\n", &.{v(actType), v(expType)});
        return false;
    }
}

pub fn eq(vm: *cy.UserVM, args: [*]const Value, nargs: u8) linksection(cy.StdSection) Value {
    _ = nargs;
    const act = args[0];
    const exp = args[1];
    defer {
        vm.release(act);
        vm.release(exp);
    }
    if (eq2(vm, act, exp)) {
        return Value.True;
    } else {
        return vm.prepareThrowSymbol(@enumToInt(Symbol.AssertError));
    }
}

pub fn eqNear(vm: *cy.UserVM, args: [*]const Value, nargs: u8) Value {
    _ = nargs;
    const act = args[0];
    const exp = args[1];

    const actType = act.getUserTag();
    const expType = exp.getUserTag();
    if (actType == expType) {
        if (actType == .number) {
            if (std.math.approxEqAbs(f64, act.asF64(), exp.asF64(), 1e-5)) {
                return Value.True;
            } else {
                printStderr("actual: {} != {}\n", &.{v(act.asF64()), v(exp.asF64())});
                return prepareThrowSymbol(vm, .AssertError);
            }
        } else {
            printStderr("Expected number, actual: {}\n", &.{v(actType)});
            return prepareThrowSymbol(vm, .AssertError);
        }
    } else {
        printStderr("Types do not match:\n", &.{});
        printStderr("actual: {} != {}\n", &.{v(actType), v(expType)});
        return prepareThrowSymbol(vm, .AssertError);
    }
}

pub fn eqList(vm: *cy.UserVM, args: [*]const Value, _: u8) Value {
    const act = args[0];
    const exp = args[1];
    defer {
        vm.release(act);
        vm.release(exp);
    }

    const actType = act.getUserTag();
    const expType = exp.getUserTag();
    if (actType == expType) {
        if (actType == .list) {
            const acto = act.asHeapObject();
            const expo = exp.asHeapObject();
            if (acto.list.list.len == expo.list.list.len) {
                var i: u32 = 0;
                const actItems = acto.list.items();
                const expItems = expo.list.items();
                while (i < acto.list.list.len) : (i += 1) {
                    if (!eq2(vm, actItems[i], expItems[i])) {
                        printStderr("Item mismatch at idx: {}\n", &.{v(i)});
                        return prepareThrowSymbol(vm, .AssertError);
                    }
                }
                return Value.True;
            } else {
                printStderr("actual list len: {} != {}\n", &.{v(acto.list.list.len), v(expo.list.list.len)});
                return prepareThrowSymbol(vm, .AssertError);
            }
        } else {
            printStderr("Expected list, actual: {}\n", &.{v(actType)});
            return prepareThrowSymbol(vm, .AssertError);
        }
    } else {
        printStderr("Types do not match:\n", &.{});
        printStderr("actual: {} != {}\n", &.{v(actType), v(expType)});
        return prepareThrowSymbol(vm, .AssertError);
    }
}

fn printStderr(format: []const u8, vals: []const fmt.FmtValue) void {
    if (!cy.silentError) {
        fmt.printStderr(format, vals);
    }
}