-- Create libfoo.so using clang:
-- clang -shared -o libfoo.so foo.c

-- Create libfoo.so using gcc:
-- gcc -c -fPIC foo.c -o foo.o
-- gcc -shared foo.o -o libfoo.so

import os 'os'

lib = os.bindLib('./libfoo.so', [
    os.CFunc{ sym: 'add', args: [#int, #int], ret: #int }
])
lib.add(123, 321)
