import t 'test'

-- Temporary rc if expr cond is released before entering body. (cond always evaluates true for rc objects)
a = if string(1) then 123 else false

-- Temporary rc if stmt cond is released before entering body. (cond always evaluates true for rc objects)
if string(1):
    pass

-- Temporary rc else cond is released before entering body. 
if false:
    pass
else string(1):
    pass

-- Temporary rc where cond is released before entering body.
while string(1):
    break

-- b's narrow type becomes `any` after the if branch, `a = b` should generate copyRetainSrc.
b = []
if false:
    b = 123
a = b

-- Binary metatype operand does not reuse dst for temp since it is retained.
f = func():
    return number == boolean
f()

-- if expr returns rcCandidate value if else clause is a RC string and if clause is a non-RC string.
b = 123
a = if false then 'abc' else '{b}'
c = '{a}'  -- If `a` isn't marked as a rcCandidate, `a` would be freed here and at the end of the block.