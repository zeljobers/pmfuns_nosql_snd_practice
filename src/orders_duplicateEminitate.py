import csv
r_customers = csv.reader(open("orders_dataset.csv", "r"),delimiter=",")
w = csv.writer(open("2orders_dataset.csv", "w"))
skip_list = []
for row_c in r_customers:
    if row_c[0] + "," + row_c[1] + "," + row_c[2] not in skip_list:
        w.writerow(row_c);
        skip_list.append(row_c[0] + "," + row_c[1] + "," + row_c[2])