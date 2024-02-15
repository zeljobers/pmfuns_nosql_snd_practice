import csv
r_customers = csv.reader(open("customers_dataset.csv", "r"),delimiter=",")
w = csv.writer(open("customers_dataset1.csv", "w"))
skip_list = []
for row_c in r_customers:
    if row_c[1] not in skip_list:
        w.writerow(row_c);
        skip_list.append(row_c[1])