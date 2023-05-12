try:
    range = xrange
except NameError:
    pass

list = list(range(0, 1000000))
sum = 0
for i in list:
  sum += i
print(sum)