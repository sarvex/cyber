count = 0

def inc():
    global count
    count += 1
    yield
    count += 1
    yield

list = []
for _ in range(0, 100000):
    f = inc()
    next(f)
    list.append(f)

for f in list:
    next(f)

print(count)
