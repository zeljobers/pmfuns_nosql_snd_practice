CALL gds.graph.project.cypher(
  'products',
  'MATCH (n:Product) RETURN id(n) AS id',
  'MATCH (n:Product)-[r:COMPARED_NUMBER_OF_CUSTOMERS_WITH]->(m:Product) 
        RETURN id(n) AS source, 
                     id(m) AS target,
                     r.ratio AS ratio')
YIELD
  graphName AS graph, 
  nodeQuery, 
  nodeCount AS nodes, 
  relationshipQuery, 
  relationshipCount AS rels;

//---1 - centrality

CALL gds.pageRank.stream('products', {relationshipWeightProperty: "ratio"})
YIELD nodeId, score
WITH gds.util.asNode(nodeId).product_id AS name, score
RETURN collect(name), score
ORDER BY score ASC
// --- estimation 
CALL gds.pageRank.write.estimate('products', {
  relationshipWeightProperty: "ratio",
  writeProperty: 'pageRank',
  maxIterations: 20,
  dampingFactor: 0.85
})
YIELD nodeCount, relationshipCount, bytesMin, bytesMax, requiredMemory
// --- stats
CALL gds.pageRank.stats('products', {
  relationshipWeightProperty: "ratio",
  maxIterations: 20,
  dampingFactor: 0.85
})
YIELD centralityDistribution
RETURN centralityDistribution;

// ---2
CALL gds.degree.stream('products', {relationshipWeightProperty: "ratio"})
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).product_id AS name, score AS followers
ORDER BY followers DESC, name DESC;

//============ PRODUCTS' COMMON SELLERS ======================com det + path find
  CALL gds.graph.project.cypher(
  'products_sellers',
  'MATCH (n:Product) RETURN id(n) AS id',
  'MATCH (n:Product)-[r:HAS_COMMON_SELLERS_WITH]->(m:Product) 
        RETURN id(n) AS source, 
                     id(m) AS target,
                     r.amount_of_sellers AS amount_of_sellers')
YIELD	
  graphName AS graph, 
  nodeQuery, 
  nodeCount AS nodes, 
  relationshipQuery, 
  relationshipCount AS rels;
//--- 1
  CALL gds.alpha.maxkcut.stream('products_sellers', {relationshipWeightProperty: "amount_of_sellers"})
YIELD nodeId, communityId
RETURN gds.util.asNode(nodeId).product_id AS name, communityId;

	// all together community id assigning
CALL gds.alpha.maxkcut.stream('products_sellers',{relationshipWeightProperty: "amount_of_sellers"})
YIELD nodeId, communityId
WITH gds.util.asNode(nodeId).product_id AS name, communityId
RETURN collect(name), communityId;
//----2
CALL gds.louvain.stream('products_sellers', {relationshipWeightProperty: "amount_of_sellers"})
YIELD nodeId, communityId, intermediateCommunityIds
RETURN gds.util.asNode(nodeId).product_id AS name, communityId, intermediateCommunityIds
ORDER BY name ASC;

CALL gds.louvain.stream('products_sellers', {relationshipWeightProperty: "amount_of_sellers"})
YIELD nodeId, communityId, intermediateCommunityIds
WITH gds.util.asNode(nodeId).product_id AS name, communityId, intermediateCommunityIds
RETURN collect(name), communityId;
//-----3
CALL gds.labelPropagation.stream('products_sellers', {relationshipWeightProperty: "amount_of_sellers"})
YIELD nodeId, communityId AS Community
RETURN gds.util.asNode(nodeId).product_id AS Name, Community
ORDER BY Community, Name;

CALL gds.labelPropagation.stream('products_sellers', {relationshipWeightProperty: "amount_of_sellers"})
YIELD nodeId, communityId AS Community
WITH gds.util.asNode(nodeId).product_id AS Name, Community
RETURN collect(Name), Community;

// -- PATH FINDING ----------------------------------------
MATCH (source:Product)
with source 
order by source.product_id desc limit 1
CALL gds.allShortestPaths.dijkstra.stream('products_sellers', {
    sourceNode: source,
    relationshipWeightProperty: 'amount_of_sellers'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
WHERE sourceNode <> targetNode
RETURN
    index,
    gds.util.asNode(sourceNode).product_id AS sourceNodeName,
    gds.util.asNode(targetNode).product_id AS targetNodeName,
    totalCost,
    [nodeId IN nodeIds | gds.util.asNode(nodeId).product_id] AS nodeNames,
    costs,
    nodes(path) as path
ORDER BY costs desc, index asc;

// -- SIMILARITY =================================================
// create graph catalog projection
CALL gds.graph.project.cypher(
    'product_nodes',
    'MATCH (n) WHERE n:Product RETURN
    id(n) AS id, labels(n) AS labels,
    CASE n.product_weight_g WHEN "Undefined" then 0 else n.product_weight_g end as product_weight_g,
    CASE n.product_width_cm WHEN "Undefined" then 0 else n.product_width_cm end as product_width_cm,
    CASE n.product_height_cm WHEN "Undefined" then 0 else n.product_height_cm end as product_height_cm,
    CASE n.product_length_cm WHEN "Undefined" then 0 else n.product_length_cm end as product_length_cm', 
    'MATCH (n:Product)-[r]->(m:Product) return id(n) AS source, id(m) AS target, type(r) AS type');
YIELD graphName, nodeCount AS nodes, relationshipCount AS rels
RETURN graphName, nodes, rels

// -------------------- high differences
CALL gds.knn.stream('product_nodes', {
    topK: 1,
    nodeProperties: ['product_weight_g','product_width_cm', 'product_height_cm','product_length_cm'],
    // The following parameters are set to produce a deterministic result
    randomSeed: 1337,
    concurrency: 1,
    sampleRate: 1.0,
    deltaThreshold: 0.0
})
YIELD node1, node2, similarity
RETURN gds.util.asNode(node1).product_id AS Person1, gds.util.asNode(node2).product_id AS Person2, similarity
ORDER BY similarity asc, Person1, Person2

// --- NODE EMBEDDING =============================================
// create graph catalog projection
CALL gds.graph.project('poc_graph', ['Product', 'Order', 'Customer'], ['ORDERED', 'FOR_PRODUCT_OF']);

// real deal -----
CALL gds.beta.node2vec.stream('poc_graph', {embeddingDimension: 2})
YIELD nodeId, embedding
RETURN nodeId, embedding

// --- Link Prediction (topoplogical one) =========================================
 MATCH (p1:Product)
 MATCH (p2:Product)
 WHERE p1 <> p2
WITH gds.alpha.linkprediction.totalNeighbors(p1, p2, {relationshipQuery: 'FOR_PRODUCT_OF'}) AS score, p1,p2 LIMIT 20
 RETURN score, p1.product_id, p2.product_id ORDER BY score desc




// ======================================================
// ======================================================
// ======================================================
// ======================================================
CALL gds.graph.project.cypher(
  'persons',
  'MATCH (n:Person) RETURN id(n) AS id',
  'MATCH (n:Person)-[r:KNOWS]->(m:Person) RETURN id(n) AS source, id(m) AS target')
YIELD
  graphName AS graph, 
  nodeQuery, 
  nodeCount AS nodes, 
  relationshipQuery, 
  relationshipCount AS rels;
//----
CALL gds.graph.streamRelationshipProperty('readWithProperties', 'numberOfPages')
YIELD sourceNodeId, targetNodeId, propertyValue AS numberOfPages
RETURN
  gds.util.asNode(sourceNodeId).name AS person,
  gds.util.asNode(targetNodeId).name AS book,
  numberOfPages
ORDER BY person ASC, numberOfPages DESC;
//--
CALL gds.pageRank.stream('products')
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).name AS name, score
ORDER BY score DESC, name ASC  ;

///==============================================================
