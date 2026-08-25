import time


#best peformance so far when running only in terminal: 8280000 : 1.0054s AVG over 8 samples



def one_second_delay():
    iterations = 2_600_000   # tuned for Pi 4B @ 1.5GHz
    
    i = 0
    while i < iterations:
        i += 1
start = time.perf_counter()
one_second_delay()
elapsed = time.perf_counter() - start
print(elapsed)

# num_trials = 30
# times = []
# 
# for trial in range(num_trials):
#     start = time.perf_counter()
#     one_second_delay()
#     elapsed = time.perf_counter() - start
#     times.append(elapsed)
# 
# average_time = sum(times)/len(times)
# min_time = min(times)
# max_time = max(times)
# 
# print(f" average time:  {average_time} s")
# print(f" min time:  {min_time} s")
# print(f" max time:  {max_time} s")