import time

str = 'abcdefghijklmnopqrstuvwxyz123456' * 1000000 + 'waldo'

start = time.process_time()
for _ in range(50):
    idx = str.find('waldo')
print(f'idx: {idx} ms: {(time.process_time() - start) * 1000}')