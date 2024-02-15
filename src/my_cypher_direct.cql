// NE ZABORAVI DA STAVIS TIPOVE PODATAKA SVOJSTAVA NA NORMALAN NACIN
CREATE CONSTRAINT ON (c:Customer) ASSERT c.customer_combined_id IS UNIQUE;
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///customers_dataset.csv" AS customer_line
MERGE (customer: Customer {
	customer_combined_id: customer_line.customer_id + customer_line.customer_unique_id,
    customer_unique_id: customer_line.customer_unique_id,
    customer_id: customer_line.customer_id,
    customer_zip_code_prefix: customer_line.customer_zip_code_prefix,
    customer_city: customer_line.customer_city,
    customer_state: customer_line.customer_state               
})

MATCH (n) REMOVE n.customer_city, n.customer_state
///

CREATE CONSTRAINT ON (o:Order) ASSERT o.order_combined_id IS UNIQUE;

:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///order_items_dataset.csv" AS order_items_line
MERGE (order:Order {
	order_combined_id:  order_items_line.order_id + order_items_line.order_item_id,
	order_id: order_items_line.order_id,
	order_item_id: order_items_line.order_item_id,
	product_id: order_items_line.product_id,
	seller_id: order_items_line.seller_id,
	shipping_limit_date: order_items_line.shipping_limit_date,
	price: order_items_line.price,
	freight_value: order_items_line.freight_value
})

// convert and update datetime property TODO

// convert to string numbers to integers TODO

// make a(n) connection/edge/branch for order-customer without any combinational id
:auto USING PERIODIC COMMIT 500 LOAD CSV WITH HEADERS FROM "file:///1orders_dataset.csv" AS orders_line
MATCH (o:Order{order_id: orders_line.order_id}),(c:Customer{customer_id: orders_line.customer_id}) 
CREATE (o)<-[ordered:ORDERED {
	order_status: orders_line.order_status,
	order_purchase_timestamp: orders_line.order_purchase_timestamp,
	order_approved_at: orders_line.order_approved_at,
	order_delivered_carrier_date: orders_line.order_delivered_carrier_date,
	order_delivered_customer_date: orders_line.order_delivered_customer_date,
	order_estimated_delivery_date: orders_line.order_estimated_delivery_date
}]-(c)

// seller

CREATE CONSTRAINT ON (s: Seller) ASSERT s.seller_id IS UNIQUE;

:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///sellers_dataset.csv" AS seller_line
MERGE (seller:Seller {
	seller_id: seller_line.seller_id
})
 SET seller.seller_zip_code_prefix = seller_line.seller_zip_code_prefix;

// make product
CREATE CONSTRAINT ON (p:Product) ASSERT p.product_id IS UNIQUE;

:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///1products_dataset.csv" AS product_line 
MERGE (
	product: Product {					
		product_id: product_line.product_id,
		product_category_name: product_line.product_category_name,
		product_name_lenght: product_line.product_name_lenght,
		product_description_lenght: product_line.product_description_lenght,
		product_photos_qty: product_line.product_photos_qty,
		product_weight_g: product_line.product_weight_g,
		product_length_cm: product_line.product_length_cm,
		product_height_cm: product_line.product_height_cm,
		product_width_cm: product_line.product_width_cm

	}
);

// rel prod - order
MATCH (o:Order),(p:Product) WHERE o.product_id = p.product_id 
MERGE (o)-[:FOR_PRODUCT_OF]->(p);

// rel sel - ord
MATCH (s:Seller),(o:Order) WHERE o.seller_id = s.seller_id 
MERGE (o)-[:OFFERED_BY]->(s);

//evo ga geolocation!!
CREATE CONSTRAINT ON (g:Possible_location) ASSERT g.geolocation IS UNIQUE;
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///1geolocation_dataset.csv" AS geolocation_line
MERGE (	geolocation:Possible_location{
	geolocation_zip_code_prefix: toInteger(geolocation_line.geolocation_zip_code_prefix),
	geolocation: geolocation_line.geolocation_lat + "," + geolocation_line.geolocation_lng,
    geolocation_lat: toFloat(geolocation_line.geolocation_lat),
    geolocation_lng: toFloat(geolocation_line.geolocation_lng),
    geolocation_city: geolocation_line.geolocation_city,
    geolocation_state: geolocation_line.geolocation_state
})
// rel seller - located at - possible_loc
MATCH (s:Seller),(p:Possible_location) WHERE s.seller_zip_code_prefix = p.geolocation_zip_code_prefix
MERGE (s)-[:POSSIBLY_LOCATED_AT]->(p);

// rel customer - located at - possible_loc // UBRZANO
:auto MATCH (c:Customer),(p:Possible_location) WHERE c.customer_zip_code_prefix = p.geolocation_zip_code_prefix
CALL { WITH c,p
CREATE (c)-[:POSSIBLY_LOCATED_AT]->(p)
} IN TRANSACTIONS OF 10000 ROWS;

/// make a payment rel
:auto USING PERIODIC COMMIT 500 LOAD CSV WITH HEADERS FROM "file:///order_payments_dataset.csv" AS payment_line
MATCH (o:Order{order_id: payment_line.order_id})<-[ord:ORDERED]-(c:Customer) 
CREATE (o)<-[payment:PURCHASED {
	
	payment_sequential: toInteger(payment_line.payment_sequential),
	payment_type: payment_line.payment_type,
	payment_installments: toInteger(payment_line.payment_installments),
	payment_value: toInteger(payment_line.payment_value)
}]-(c)

// moze da se desi da customer-a nema za order...

/// make a review rel
// relation review for cust-order -----
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///order_reviews_dataset.csv" AS review_line
MATCH (o:Order{order_id: review_line.order_id})<-[ord:ORDERED]-(c:Customer) 
CREATE (o)<-[r:REVIEWED {
	review_id: review_line.review_id,
	review_score: toInteger(review_line.review_score),
	review_comment_title: review_line.review_comment_title,
	review_comment_message: review_line.review_comment_message,
	review_creation_date: review_line.review_creation_date,
	review_answer_timestamp: review_line.review_answer_timestamp
}]-(c)



// pravljenje veze zajednickih sellera
:auto MATCH (p)<-[:FOR_PRODUCT_OF]-(:Order)-[:OFFERED_BY]->(s) 
WITH
	count(distinct s) as n_s, 
	p as p,
	collect(s) as ss 
ORDER BY n_s desc
UNWIND ss as sx
WITH
	sx as sx,
	p as p
MATCH (p1)<-[:FOR_PRODUCT_OF]-(:Order)-[:OFFERED_BY]->(sx)
WHERE p1 < p
WITH 
	p1 as p1,
	p as p,
	count(distinct sx) as n_s
CALL{
	WITH 
		p1 as p1,
		n_s as n_s,
		p as p
	CREATE 
		(p1)<-[:HAS_COMMON_SELLERS_WITH {amount_of_sellers: n_s}]-(p),
		(p)<-[:HAS_COMMON_SELLERS_WITH {amount_of_sellers: n_s}]-(p1)
} IN TRANSACTIONS OF 10000 ROWS;

// making of ratio comparison products - customers 
:auto MATCH (p)<-[:FOR_PRODUCT_OF]-(:Order)<-[:ORDERED]-(c) 
WITH
	count(distinct c) as n_c, 
	p as p
MATCH (p1)<-[:FOR_PRODUCT_OF]-(:Order)<-[:ORDERED]-(c1) 
WHERE p1 < p
WITH 
	count(distinct c1) as n_c1, 
	p1 as p1,
	p as p,
	n_c as n_c
CALL{
	WITH 
		n_c1 as n_c1, 
		p1 as p1,
		p as p,
		n_c as n_c
	CREATE (p)-[:COMPARED_NUMBER_OF_CUSTOMERS_WITH {ratio: n_c*1.0/n_c1}]->(p1),
	(p1)-[:COMPARED_NUMBER_OF_CUSTOMERS_WITH {ratio: n_c1*1.0/n_c}]->(p)
} IN TRANSACTIONS OF 10000 ROWS;

 ====================================================================== ====================================================================== ====================================================================== ====================================================================== ====================================================================== ======================================================================














CREATE CONSTRAINT ON (g:Possible_location) ASSERT g.geolocation_destination IS UNIQUE;
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///geolocation_dataset.csv" AS geolocation_line
MERGE (geolocation: Possible_location {
	geolocation_destination: geolocation_line.geolocation_lat+ "," + geolocation_line.geolocation_lng,
	geolocation_zip_code_prefix: geolocation_line.geolocation_zip_code_prefix,
	geolocation_lat: geolocation_line.geolocation_lat,
	geolocation_lng: geolocation_line.geolocation_lng,
	geolocation_city: geolocation_line.geolocation_city,
	geolocation_state: geolocation_line.geolocation_state
})
MATCH (c:Customer {customer_zip_code_prefix: geolocation.geolocation_zip_code_prefix})
MERGE (c)-[:IS_LOCATED_IN]->(geolocation)
/// ----------------
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///geolocation_dataset.csv" AS geolocation_line

MERGE (geolocation: Possible_location {
	geolocation_destination: geolocation_line.geolocation_lat+ "," + geolocation_line.geolocation_lng,
	geolocation_zip_code_prefix: geolocation_line.geolocation_zip_code_prefix,
	geolocation_lat: geolocation_line.geolocation_lat,
	geolocation_lng: geolocation_line.geolocation_lng,
	geolocation_city: geolocation_line.geolocation_city,
	geolocation_state: geolocation_line.geolocation_state
})

MERGE (c)-[:IS_LOCATED_IN]->(geolocation)
// ---

MATCH ()

/// MNOGO SPORO - RADI ali MNOOOGO SPORO
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///geolocation_dataset.csv" AS geolocation_line
MERGE (geolocation: Possible_location { // <--- ovde idu unique propertijevi
	
	geolocation_lat: geolocation_line.geolocation_lat,
	geolocation_lng: geolocation_line.geolocation_lng,
	geolocation_city: geolocation_line.geolocation_city,
	geolocation_state: geolocation_line.geolocation_state
}) /// v-- ovde idu ostali propertijevi
ON MATCH SET geolocation.geolocation_zip_code_prefix = geolocation_line.geolocation_zip_code_prefix
ON MATCH SET geolocation.geolocation_city = geolocation_line.geolocation_city
ON MATCH SET geolocation.geolocation_state = geolocation_line.geolocation_state

/// ----- SPORO RADI ZATO STO LOADCSV + REPLACE + DATETIME

CREATE CONSTRAINT ON (o:Order) ASSERT o.order_combinded_id IS UNIQUE;
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///order_items_dataset.csv" AS order_items_line
MERGE (order:Order {
	order_combined_id:  order_items_line.order_id + order_items_line.order_item_id,
	order_id: order_items_line.order_id,
	order_item_id: order_items_line.order_item_id,
	product_id: order_items_line.product_id,
	seller_id: order_items_line.seller_id,
	shipping_limit_date: datetime(REPLACE(order_items_line.shipping_limit_date, " ", "T")),
	price: order_items_line.price,
	freight_value: order_items_line.freight_value
})


	// kako jos sa datumima
	MATCH (article:Article)
	RETURN article.title AS title,
		   apoc.temporal.format(article.created, "dd MMMM yyyy HH:mm") AS created,
		   apoc.temporal.format(article.datePublished,"dd MMMM yyyy") AS datePublished,
		   apoc.temporal.format(article.readingTime, "mm:ss") AS readingTime

// --- bez coalesce
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///orders_dataset.csv" AS orders_line
MATCH (o:Order{order_id: orders_line.order_id}),(c:Customer{customer_id: orders_line.customer_id}) 
MERGE (o)<-[ordered:ORDERED {
	order_id: orders_line.order_id,
	order_status: orders_line.order_status,
	order_purchase_timestamp: orders_line.order_purchase_timestamp,
	order_approved_at: orders_line.order_approved_at,
	order_delivered_carrier_date: orders_line.order_delivered_carrier_date,
	order_delivered_customer_date: orders_line.order_delivered_customer_date,
	order_estimated_delivery_date: orders_line.order_estimated_delivery_date
}]-(c)

// --- bez coalesce
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///orders_dataset.csv" AS orders_line
MATCH (o:Order{order_id: orders_line.order_id}),(c:Customer{customer_id: orders_line.customer_id}) 
MERGE (o)<-[ordered:ORDERED {
	order_id: orders_line.order_id,
	order_status: orders_line.order_status,
	order_purchase_timestamp: orders_line.order_purchase_timestamp,
	order_approved_at: orders_line.order_approved_at,
	order_delivered_carrier_date: orders_line.order_delivered_carrier_date,
	order_delivered_customer_date: orders_line.order_delivered_customer_date,
	order_estimated_delivery_date: orders_line.order_estimated_delivery_date
}]-(c)

/// ***** MATCH p=(c:Customer{customer_zip_code_prefix:"20780"})-[r:ORDERED]->(:Order) RETURN p

// make a(n) connection/edge/branch for order-customer - 
// MNOOOGO SPORO 
// -  - COALESCE UZME DUSU VREMENSKI, BOLJE RUCNO ZAMENITI SA UNDEFINED I CAO
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///orders_dataset.csv" AS orders_line
WITH orders_line, COALESCE(CASE orders_line.order_delivered_carrier_date WHEN '' THEN null ELSE orders_line.order_delivered_carrier_date END, 'Undefined') AS delivered_carrier_date,
COALESCE(CASE orders_line.order_delivered_customer_date WHEN '' THEN null ELSE orders_line.order_delivered_customer_date END, 'Undefined') AS delivered_customer_date,
COALESCE(CASE orders_line.order_estimated_delivery_date WHEN '' THEN null ELSE orders_line.order_estimated_delivery_date END, 'Undefined') AS estimated_delivery_date,
COALESCE(CASE orders_line.order_approved_at WHEN '' THEN null ELSE orders_line.order_approved_at END, 'Undefined') AS approved_at
MATCH (o:Order{order_id: orders_line.order_id}),(c:Customer{customer_id: orders_line.customer_id}) 
MERGE (o)<-[ordered:ORDERED {
	order_customer_combo_id: orders_line.order_id + orders_line.customer_id,
	order_status: orders_line.order_status,
	order_purchase_timestamp: orders_line.order_purchase_timestamp,
	order_approved_at: approved_at,
	order_delivered_carrier_date: delivered_carrier_date,
	order_delivered_customer_date: delivered_customer_date,
	order_estimated_delivery_date: estimated_delivery_date
}]-(c)


// --- bez coalesce
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///1orders_dataset.csv" AS orders_line
MATCH (o:Order{order_id: orders_line.order_id}),(c:Customer{customer_id: orders_line.customer_id}) 
MERGE (o)<-[ordered:ORDERED {
	order_customer_combo_id: orders_line.order_id + orders_line.customer_id,
	order_status: orders_line.order_status,
	order_purchase_timestamp: orders_line.order_purchase_timestamp,
	order_approved_at: orders_line.order_approved_at,
	order_delivered_carrier_date: orders_line.order_delivered_carrier_date,
	order_delivered_customer_date: orders_line.order_delivered_customer_date,
	order_estimated_delivery_date: orders_line.order_estimated_delivery_date
}]-(c)


// bin/cypher-shell --database=neo4j 'USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///1orders_dataset.csv" AS orders_line
// #532C2C#532C2C#532C2C#FFFFFF#FFFFFFMATCH (o:Order{order_id: orders_line.order_id}),(c:Customer{customer_id: orders_line.customer_id}) MERGE (o)<-[ordered:ORDERED {	order_customer_combo_id: orders_line.order_id + orders_line.customer_id,	order_status: orders_line.order_status,	order_purchase_timestamp: orders_line.order_purchase_timestamp,	order_approved_at: orders_line.order_approved_at,	order_delivered_carrier_date: orders_line.order_delivered_carrier_date,	order_delivered_customer_date: orders_line.order_delivered_customer_date,	order_estimated_delivery_date: orders_line.order_estimated_delivery_date}]-(c)'

// make seller
"seller_id","seller_zip_code_prefix","seller_city","seller_state"

CREATE CONSTRAINT ON (s: Seller) ASSERT s.seller_id IS UNIQUE;
:auto USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM "file:///sellers_dataset.csv" AS seller_line
MERGE (seller:Seller {
	seller_id: seller_line.seller_id,
	seller_zip_code_prefix: seller_line.seller_zip_code_prefix
})

// brisanje
:auto MATCH (n:Possible_location) 
CALL { WITH n
DELETE n
} IN TRANSACTIONS OF 10000 ROWS;

// ------------------------

// boosted even more?? (at least it actually uses 2G) // make a(n) connection/edge/branch for order-customer
:auto LOAD CSV WITH HEADERS FROM "file:///1orders_dataset.csv" AS orders_line
MATCH (o:Order{order_id: orders_line.order_id}),(c:Customer{customer_id: orders_line.customer_id}) 
CALL { WITH orders_line,o,c
CREATE (o)<-[ordered:ORDERED {
	order_status: orders_line.order_status,
	order_purchase_timestamp: orders_line.order_purchase_timestamp,
	order_approved_at: orders_line.order_approved_at,
	order_delivered_carrier_date: orders_line.order_delivered_carrier_date,
	order_delivered_customer_date: orders_line.order_delivered_customer_date,
	order_estimated_delivery_date: orders_line.order_estimated_delivery_date
}]-(c)
} IN TRANSACTIONS OF 10000 ROWS;

// 2nd chance

:auto LOAD CSV WITH HEADERS FROM "file:///1orders_dataset.csv" AS orders_line
CALL { WITH orders_line
MATCH (o:Order{order_id: orders_line.order_id}),(c:Customer{customer_id: orders_line.customer_id}) 
CREATE (o)<-[ordered:ORDERED {
	order_status: orders_line.order_status,
	order_purchase_timestamp: orders_line.order_purchase_timestamp,
	order_approved_at: orders_line.order_approved_at,
	order_delivered_carrier_date: orders_line.order_delivered_carrier_date,
	order_delivered_customer_date: orders_line.order_delivered_customer_date,
	order_estimated_delivery_date: orders_line.order_estimated_delivery_date
}]-(c)
} IN TRANSACTIONS OF 10000 ROWS;

//----- NEUSPEH ^^^^^^^^^^^^^


// watching how replicated values are inserted
MATCH p=(c)-[r:ORDERED]->(o) RETURN c.customer_id,collect(o.order_id)

// by customer purchased items through variety of orders for the cetrain product(s)
MATCH p=()<-[:FOR_PRODUCT_OF]-(o:Order)<-[:PURCHASED]-(c:Customer) RETURN collect(p),count(o),c order by count(o) desc LIMIT 5
// ... offered by seller
MATCH p=()<-[:FOR_PRODUCT_OF]-(o:Order)<-[:PURCHASED]-(c:Customer),(s:Seller{seller_id: o.seller_id}) RETURN s,collect(p),count(o),c order by count(o) desc LIMIT 5

// see reviews a bit
MATCH p=()<-[:FOR_PRODUCT_OF]-(o:Order)<-[r:REVIEWED]-(c:Customer),(s:Seller{seller_id: o.seller_id}) WHERE r.review_comment_message <> "Undefined" RETURN s,collect(p),count(o),c order by count(o) desc LIMIT 5

///---------------------------------------
// cist
MATCH p=()<-[:FOR_PRODUCT_OF]-(o:Order)<-[r:REVIEWED]-(c:Customer),(s:Seller{seller_id: o.seller_id}) WHERE r.review_comment_message <> "Undefined" RETURN  o.order_id, collect(o)[0],s, c LIMIT 25

// gledanje u duplikate grane - zarad brisanja
MATCH (c)-[r:REVIEWED]->(o), (c)-[r1:REVIEWED{review_id: r.review_id}]->(o) where id(r) < id(r1) delete r 

// NE RADI //MATCH (c)-[r:REVIEWED]->(o) where r.5d69146d89990e8ea5266cb2bdaef1ee is not null return r limit 1

// product posebno, dobro
MATCH (p)<-[:FOR_PRODUCT_OF]-(o)<-[r:REVIEWED]-(c) RETURN count(distinct p),c,collect(o),collect(p) order by count(distinct p) desc LIMIT 25


MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)<-[r:REVIEWED]-(c) RETURN p,collect(o),collect(c) LIMIT 25


MATCH (p)<-[:FOR_PRODUCT_OF]-(o)<-[r:REVIEWED]-(c)-[:POSSIBLY_LOCATED_AT]->(g) RETURN count(distinct p),c,g,collect(o),collect(p) order by count(distinct p) desc LIMIT 25

// UNBLACK FRIDAYized
MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)<-[r:REVIEWED]-(c) RETURN count(distinct c), p,collect(o)[0],collect(c)[0] ORDER BY count(distinct c) desc LIMIT 5

// sellers' competition over product most wanted  by different customers 
MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s),(o)<-[:ORDERED]-(c) RETURN count(distinct s), count(distinct c), p,collect(o)[0],collect(s)[0],collect(c)[0] ORDER BY count(distinct c) desc LIMIT 25
// customers orders' attempts over product most offered by different sellers
MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s),(o)<-[:ORDERED]-(c) RETURN count(distinct s), count(distinct c), p,collect(o)[0],collect(s)[0],collect(c)[0] ORDER BY count(distinct s) desc LIMIT 25

// isto sto i gore samo jedinstven order
MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s),(o)<-[:ORDERED]-(c) WHERE o.order_item_id="1" and toInteger(o.order_item_id)=1 RETURN count(distinct s), count(distinct c), p,collect(o),collect(s),collect(c) ORDER BY count(distinct s) desc LIMIT 3

MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s),(o)<-[:ORDERED]-(c) RETURN abs(count(distinct c) - (0.0 + count(distinct c)) / count(distinct s)), count(distinct s), count(distinct c), p,collect(o)[0],collect(s)[0],collect(c)[0] ORDER BY abs(count(distinct c) - (0.0 + count(distinct c)) / count(distinct s)) desc LIMIT 200

MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s),(o)<-[:ORDERED]-(c) RETURN count(distinct s), count(distinct c), p,collect(o),collect(s),collect(c)[0] ORDER BY count(distinct s) desc, count(distinct c) desc LIMIT 2

MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s),
(p1:Product)<-[:FOR_PRODUCT_OF]-(o1:Order{order_item_id: o.order_item_id})-[:OFFERED_BY]->(s)
 WHERE p1.product_id <> p.product_id and o.order_item_id ="1" RETURN  p1.product_id,p.product_id limit 25
 
 MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s),
(p1)<-[:FOR_PRODUCT_OF]-(o1:Order{order_item_id: o.order_item_id})-[:OFFERED_BY]->(s)
 WHERE p1.product_id <> p.product_id and o.order_item_id ="1" and o <> o1 RETURN  p1.product_id, p.product_id, count(s.seller_id) limit 25

// with - return
MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s),(o)<-[:ORDERED]-(c) WITH count(distinct s) as num_sellers, count(distinct c) as num_ustomers, p as p,collect(o) as orders,collect(s) as sellers,collect(c) as customers ORDER BY count(distinct s) desc LIMIT 25
RETURN p,num_sellers

MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s),(o)<-[:ORDERED]-(c) WITH count(distinct s) as num_sellers, count(distinct c) as num_ustomers, p as p,collect(o) as orders,collect(s) as sellers,collect(c) as customers ORDER BY count(distinct s) desc LIMIT 25
WITH p,collect(sellers) as sellers_per_product
with collect(sellers_per_product) as sellers
with reduce(common_sellers = head(sellers), seller in tail(sellers) | apoc.coll.intersection(common_sellers,seller)) as common_sellers
RETURN common_sellers

// for a millionth time, finding common seller over a product
MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s) 
WITH count(distinct s) as n_s, 
p as p,
collect(o) as os,
collect(distinct s) as ss ORDER BY count(distinct s) desc LIMIT 25
UNWIND ss as sx
WITH sx as sx
MATCH (p1)<-[]-(:Order)-[]->(sx), (p)<-[]-(:Order)-[]->(sx)
WHERE p1 <> p
RETURN p1,p,count(distinct sx)

MATCH (p)<-[:FOR_PRODUCT_OF]-(o:Order)-[r:OFFERED_BY]->(s) 
WITH count(distinct s) as n_s, 
p as p,
collect(o) as os,
collect(distinct s) as ss ORDER BY count(distinct s) desc LIMIT 25
UNWIND ss as sx
WITH sx as sx,p as p, os as os
MATCH (p1)<-[]-(o1:Order)-[]->(sx)
WHERE p1 < p
RETURN p1,p,collect(o1), os,count(distinct sx), collect(sx) ORDER BY count(distinct sx) desc

:auto MATCH (p)<-[:FOR_PRODUCT_OF]-(:Order)-[:OFFERED_BY]->(s) 
WITH
	count(distinct s) as n_s, 
	p as p,
	collect(s) as ss 
ORDER BY n_s desc
UNWIND ss as sx
	WITH
		sx as sx,
		p as p
	MATCH (p1)<-[:FOR_PRODUCT_OF]-(:Order)-[:OFFERED_BY]->(sx)
	WHERE p1 < p
	RETURN 
		p1,
		p,
		count(distinct sx)
	ORDER BY count(distinct sx) desc

// konacno pravljenje veze zajednickih sellera
:auto MATCH (p)<-[:FOR_PRODUCT_OF]-(:Order)-[:OFFERED_BY]->(s) 
WITH
	count(distinct s) as n_s, 
	p as p,
	collect(s) as ss 
ORDER BY n_s desc
UNWIND ss as sx
WITH
	sx as sx,
	p as p
MATCH (p1)<-[:FOR_PRODUCT_OF]-(:Order)-[:OFFERED_BY]->(sx)
WHERE p1 < p
WITH 
	p1 as p1,
	p as p,
	count(distinct sx) as n_s
CALL{
	WITH 
		p1 as p1,
		n_s as n_s,
		p as p
	CREATE 
		(p1)<-[:HAS_COMMON_SELLERS {amount_of_sellers: n_s}]-(p),
		(p)<-[:HAS_COMMON_SELLERS {amount_of_sellers: n_s}]-(p1)
} IN TRANSACTIONS OF 10000 ROWS;
//----------------
// making of ratio comparison products - customers 
//ispis
:auto MATCH (p)<-[:FOR_PRODUCT_OF]-(:Order)<-[:ORDERED]->(c) 
WITH
	count(distinct c) as n_c, 
	p as p
	ORDER BY n_c desc
MATCH (p1)<-[:FOR_PRODUCT_OF]-(:Order)<-[:ORDERED]->(c1) 
WHERE p1 < p
WITH 
	count(distinct c1) as n_c1, 
	p1 as p1,
	p as p,
	n_c as n_c
CALL{
	WITH 
		n_c1 as n_c1, 
		p1 as p1,
		p as p,
		n_c as n_c
	RETURN n_c*1.0/n_c1, p,p1
} IN TRANSACTIONS OF 10000 ROWS; // OVO NE MOZE ZA RETURN!

// konacan // making of ratio comparison products - customers 

:auto MATCH (p)<-[:FOR_PRODUCT_OF]-(:Order)<-[:ORDERED]-(c) 
WITH
	count(distinct c) as n_c, 
	p as p
MATCH (p1)<-[:FOR_PRODUCT_OF]-(:Order)<-[:ORDERED]-(c1) 
WHERE p1 < p
WITH 
	count(distinct c1) as n_c1, 
	p1 as p1,
	p as p,
	n_c as n_c
CALL{
	WITH 
		n_c1 as n_c1, 
		p1 as p1,
		p as p,
		n_c as n_c
	CREATE (p)-[:COMPARED_NUMBER_OF_CUSTOMERS_WITH {ratio: n_c*1.0/n_c1}]->(p1),
	(p1)-[:COMPARED_NUMBER_OF_CUSTOMERS_WITH {ratio: n_c1*1.0/n_c}]->(p)
} IN TRANSACTIONS OF 10000 ROWS;


// konacan seller ratio
:auto MATCH (p)<-[:FOR_PRODUCT_OF]-(:Order)-[:OFFERED_BY]->(s) 
WITH
	count(distinct s) as n_s, 
	p as p
MATCH (p1)<-[:FOR_PRODUCT_OF]-(:Order)-[:OFFERED_BY]->(s1) 
WHERE p1 < p
WITH 
	count(distinct s1) as n_s1, 
	p1 as p1,
	p as p,
	n_s as n_s
CALL{
	WITH 
		n_s1 as n_s1, 
		p1 as p1,
		p as p,
		n_s as n_s
	CREATE (p)-[:COMPARED_SELLER_RATIO_WITH {seller_ratio: n_s*1.0/n_s1}]->(p1),
	(p1)-[:COMPARED_SELLER_RATIO_WITH {seller_ratio: n_s1*1.0/n_s}]->(p)
} IN TRANSACTIONS OF 1000 ROWS;

:auto MATCH (p)<-[:FOR_PRODUCT_OF]-(:Order {order_item_id: "1"})-[:OFFERED_BY]->(s) 
WITH
	count(distinct s) as n_s, 
	p as p
MATCH (p1)<-[:FOR_PRODUCT_OF]-(:Order {order_item_id: "1"})-[:OFFERED_BY]->(s1) 
WHERE p1 < p
RETURN 
	count(distinct s1) as n_s1, 
    n_s as n_s,
	p1 as p1,
	p as p
    ORDER BY n_s desc, n_s1 desc


:auto MATCH (p)<-[:FOR_PRODUCT_OF]-(:Order {order_item_id: "1"})-[:OFFERED_BY]->(s) 
WITH
	count(distinct s) as n_s, 
	p as p
WITH collect([n_s,p]) as pair_prns
UNWIND pair_prns as pair_x1
WITH pair_x1[0] as n_s1, pair_x1[1] as p1, pair_prns
UNWIND pair_prns as pair_x2
WITH n_s1, p1, pair_x2[0] as n_s2, pair_x2[1] as p2
WHERE p1 < p2
RETURN p1.product_id, n_s1, p2.product_id, n_s2

:auto MATCH (n:Possible_location) with n
MATCH (n1:Possible_location) 
WHERE n1 < n 
with n,n1, point({longitude: toFloat(n.geolocation_lng), latitude: toFloat(n.geolocation_lat)}) as p1, point({longitude: toFloat(n1.geolocation_lng), latitude: toFloat(n1.geolocation_lat)}) as p2 
with n,n1, point.distance(p1,p2) as distance_x
call {
	with n,n1, distance_x 
	create (n1)-[:DISTANCE_TO {distance: distance_x}]->(n), (n)-[:DISTANCE_TO {distance: distance_x}]->(n1)
} IN TRANSACTIONS OF 10000 ROWS;
