@import <OJUnit/OJTestCase.j>

@import "CoreData.j"


/*!
    Unit tests for CPHTTPPredicateEncoder and CPHTTPStore object-ID helpers.

    These tests exercise pure-logic paths that do not require a live HTTP
    server.  Transport-level behaviour is covered by integration tests against
    the OrdersAPI backend.
*/
@implementation CPHTTPStoreTest : OJTestCase
{
}


// ---------------------------------------------------------------------------
// CPHTTPPredicateEncoder – raw dictionary pass-through
// ---------------------------------------------------------------------------

- (void)testPredicateEncoderRawDictPassThrough
{
    var raw = [CPDictionary dictionaryWithObjectsAndKeys:
                   @"beginswith", @"op",
                   @"fullName",   @"key",
                   @"A",          @"value"];

    var result = [CPHTTPPredicateEncoder encodePredicateToAST:raw];
    [self assert:raw equals:result message:@"Raw dict should be returned unchanged"];
}

- (void)testPredicateEncoderNilReturnsNil
{
    [self assertNull:[CPHTTPPredicateEncoder encodePredicateToAST:nil]
             message:@"nil predicate should return nil"];
}


// ---------------------------------------------------------------------------
// CPHTTPStore – globalID string encoding / decoding
// ---------------------------------------------------------------------------

- (void)testGlobalIDStringSimplePK
{
    var store  = [self _makeStore],
        serverID = @{ @"entity": @"Customer", @"pk": @{ @"customerID": 1075 } };

    var result = [store _globalIDStringForServerID:serverID];
    [self assert:@"Customer|customerID=1075;" equals:result];
}

- (void)testGlobalIDStringMatchesServerFormat
{
    // The OrdersAPI uses "Customer|customerID=1075;" as objectsByID keys
    var store    = [self _makeStore],
        serverID = @{ @"entity": @"Customer", @"pk": @{ @"customerID": 1075 } };

    [self assert:@"Customer|customerID=1075;"
          equals:[store _globalIDStringForServerID:serverID]];
}

- (void)testGlobalIDStringCompositePKSorted
{
    var store    = [self _makeStore],
        serverID = @{ @"entity": @"OrderLine",
                      @"pk": @{ @"orderID": 1, @"lineNo": 2 } };

    // Keys must be sorted: lineNo < orderID
    [self assert:@"OrderLine|lineNo=2;orderID=1;"
          equals:[store _globalIDStringForServerID:serverID]];
}

- (void)testServerIDRoundTrip
{
    var store    = [self _makeStore],
        serverID = @{ @"entity": @"Order", @"pk": @{ @"orderID": 245 } },
        globalID = [store _globalIDStringForServerID:serverID],
        decoded  = [store _serverIDFromGlobalIDString:globalID entityName:@"Order"];

    [self assert:@"Order" equals:[decoded objectForKey:@"entity"]];
    var pk = [decoded objectForKey:@"pk"];
    [self assertTrue:(pk !== nil) message:@"pk should not be nil"];
    [self assert:245 equals:[pk objectForKey:@"orderID"]];
}


// ---------------------------------------------------------------------------
// CPHTTPStore – temp key encoding
// ---------------------------------------------------------------------------

- (void)testTempKeyFormat
{
    var store = [self _makeStore],
        objID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                 globalID:nil
                                              isTemporary:YES],
        key   = [store _tempKeyForObjectID:objID];

    [self assertTrue:([key length] > 2) message:@"temp key should be non-empty"];
    [self assert:@"t_" equals:key.substring(0, 2) message:@"temp key should start with t_"];
}


// ---------------------------------------------------------------------------
// CPHTTPStore – _buildFetchBody:
// ---------------------------------------------------------------------------

- (void)testBuildFetchBodyEntityOnly
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Customer"];

    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entity];

    var body = [store _buildFetchBody:req];
    [self assert:@"Customer" equals:[body objectForKey:@"entity"]];
    [self assertNull:[body objectForKey:@"predicate"]];
    [self assertNull:[body objectForKey:@"sort"]];
}

- (void)testBuildFetchBodyWithRawDictPredicate
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Customer"];

    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entity];
    var pred = @{ @"op": @"beginswith", @"key": @"fullName", @"value": @"I" };
    [req setPredicate:pred];

    var body = [store _buildFetchBody:req];
    [self assert:pred equals:[body objectForKey:@"predicate"]];
}

- (void)testBuildFetchBodyWithLimitOffset
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Order"];

    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entity];
    [req setFetchLimit:10];
    [req setFetchOffset:20];

    var body = [store _buildFetchBody:req];
    [self assert:10 equals:[body objectForKey:@"limit"]];
    [self assert:20 equals:[body objectForKey:@"offset"]];
}

- (void)testBuildFetchBodyOnlyIDsMode
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Order"];

    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entity];
    [req setTransparentFetch:YES];

    var body   = [store _buildFetchBody:req];
    var retVal = [body objectForKey:@"return"];
    [self assertNotNull:retVal];
    [self assertTrue:([retVal objectForKey:@"onlyIDs"] ? YES : NO)];
}

- (void)testBuildFetchBodyResultTypeCount
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Order"];

    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entity];
    [req setResultType:CPCountResultType];

    var body = [store _buildFetchBody:req];
    [self assert:@"count" equals:[body objectForKey:@"resultType"]];
}

- (void)testBuildFetchBodyRelationshipPrefetching
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Order"];

    var req = [[CPFetchRequest alloc] init];
    [req setEntity:entity];
    [req setRelationshipKeyPathsForPrefetching:[@"customer", @"lineItems"]];

    var body    = [store _buildFetchBody:req];
    var include = [body objectForKey:@"include"];
    [self assertNotNull:include];
    [self assert:[@"customer", @"lineItems"] equals:[include objectForKey:@"relationships"]];
    [self assert:1 equals:[include objectForKey:@"depth"]];
}


// ---------------------------------------------------------------------------
// CPHTTPStore – _toNativeObject: (JSON serialisation helper)
// ---------------------------------------------------------------------------

- (void)testToNativeObjectNil
{
    var store = [self _makeStore];
    [self assertNull:[store _toNativeObject:nil]];
}

- (void)testToNativeObjectString
{
    var store = [self _makeStore];
    [self assert:@"hello" equals:[store _toNativeObject:@"hello"]];
}

- (void)testToNativeObjectDictionary
{
    var store = [self _makeStore],
        dict  = [CPDictionary dictionaryWithObjectsAndKeys:@"val", @"key"],
        result = [store _toNativeObject:dict];
    [self assert:@"val" equals:result[@"key"]];
}

- (void)testToNativeObjectArray
{
    var store  = [self _makeStore],
        arr    = [@"a", @"b"],
        result = [store _toNativeObject:arr];
    [self assert:2 equals:result.length];
    [self assert:@"a" equals:result[0]];
}


// ---------------------------------------------------------------------------
// CPHTTPStore – _applyRelationships:toObject: inverse propagation
// ---------------------------------------------------------------------------

/*!
    When a to-many relationship is applied to an object (e.g. Order.expenses),
    the framework must automatically fill in the inverse to-one relationship on
    each related object (e.g. expense.order = Order.objectID).  This mirrors
    Apple CoreData's referential-integrity maintenance and prevents the "order
    navigation is a fault" symptom that appears when the server omits the
    back-reference from the prefetched child's relationships block.
*/
- (void)testApplyRelationships_toMany_propagatesInverseToOne
{
    // ---- Build a two-entity model: Order ←→ OrderExpense ----
    var model       = [[CPManagedObjectModel alloc] init],
        orderEntity = [[CPEntityDescription alloc] init],
        expEntity   = [[CPEntityDescription alloc] init];

    [orderEntity setName:@"Order"];
    [expEntity   setName:@"OrderExpense"];

    // Order.expenses  (to-many, inverse = "order")
    [orderEntity addRelationshipWithName:@"expenses"
                                  toMany:YES
                                optional:YES
                              deleteRule:0
                             destination:@"OrderExpense"];
    var expensesRel = [[orderEntity relationshipsByName] objectForKey:@"expenses"];
    [expensesRel setInversePropertyName:@"order"];

    // OrderExpense.order  (to-one, inverse = "expenses")
    [expEntity addRelationshipWithName:@"order"
                                toMany:NO
                              optional:YES
                            deleteRule:0
                           destination:@"Order"];
    var orderRel = [[expEntity relationshipsByName] objectForKey:@"order"];
    [orderRel setInversePropertyName:@"expenses"];

    [model addEntity:orderEntity];
    [model addEntity:expEntity];

    // ---- Create a store attached to a coordinator with that model ----
    var storeConfig = [CPDictionary dictionaryWithObject:@"http://localhost/OrdersAPI"
                                                  forKey:CPHTTPStoreBaseURL];
    var store  = [[CPHTTPStore alloc] initWithStoreID:@"test" configuration:storeConfig];
    var coordinator = [[CPPersistentStoreCoordinator alloc]
                            initWithManagedObjectModel:model
                                             storeType:[CPHTTPStoreType class]
                                    storeConfiguration:storeConfig];
    [store setStoreCoordinator:coordinator];

    // ---- Build mock materialised objects (no context needed for this test) ----
    var orderObj = [orderEntity createObject];
    var orderID  = [[CPManagedObjectID alloc] initWithEntity:orderEntity
                                                    globalID:@"Order|orderID=1;"
                                                 isTemporary:NO];
    [orderObj setObjectID:orderID];
    [orderObj setFault:NO];

    var expObj = [expEntity createObject];
    var expID  = [[CPManagedObjectID alloc] initWithEntity:expEntity
                                                  globalID:@"OrderExpense|expenseID=7;"
                                               isTemporary:NO];
    [expObj setObjectID:expID];
    [expObj setFault:NO];

    // allMaterialized maps globalID → managed object
    var allMaterialized = [CPMutableDictionary dictionaryWithObjectsAndKeys:
                               orderObj, @"Order|orderID=1;",
                               expObj,   @"OrderExpense|expenseID=7;"];

    // ---- Apply relationships: Order.expenses = [expense #7] ----
    // Simulate the server returning:
    //   relationships: { expenses: [{entity:"OrderExpense", pk:{expenseID:7}}] }
    // The server does NOT include `order` in the expense's relationships block.
    var relationships = {
        expenses: [{ entity: "OrderExpense", pk: { expenseID: 7 } }]
    };

    [store _applyRelationships:relationships
                      toObject:orderObj
               allMaterialized:allMaterialized
                       context:nil];

    // Order.expenses should contain expense's objectID
    var expensesSet = [[orderObj data] objectForKey:@"expenses"];
    [self assertNotNull:expensesSet
                message:@"Order.expenses should be non-nil after _applyRelationships:"];
    [self assert:1 equals:[expensesSet count]
         message:@"Order.expenses should contain exactly one entry"];

    // The inverse must have been propagated: expense.order should point to Order
    var orderVal = [[expObj data] objectForKey:@"order"];
    [self assertNotNull:orderVal
                message:@"expense.order should be non-nil after inverse propagation"];
    [self assert:@"Order|orderID=1;" equals:[orderVal globalID]
         message:@"expense.order globalID should match Order's globalID"];
}

/*!
    When a to-one relationship is applied to an object (e.g. expense.order),
    the framework must automatically add the source object to the inverse
    to-many on the target (e.g. Order.expenses).
*/
- (void)testApplyRelationships_toOne_propagatesInverseToMany
{
    var model       = [[CPManagedObjectModel alloc] init],
        orderEntity = [[CPEntityDescription alloc] init],
        expEntity   = [[CPEntityDescription alloc] init];

    [orderEntity setName:@"Order"];
    [expEntity   setName:@"OrderExpense"];

    [orderEntity addRelationshipWithName:@"expenses"
                                  toMany:YES
                                optional:YES
                              deleteRule:0
                             destination:@"OrderExpense"];
    var expensesRel = [[orderEntity relationshipsByName] objectForKey:@"expenses"];
    [expensesRel setInversePropertyName:@"order"];

    [expEntity addRelationshipWithName:@"order"
                                toMany:NO
                              optional:YES
                            deleteRule:0
                           destination:@"Order"];
    var orderRel = [[expEntity relationshipsByName] objectForKey:@"order"];
    [orderRel setInversePropertyName:@"expenses"];

    [model addEntity:orderEntity];
    [model addEntity:expEntity];

    var storeConfig = [CPDictionary dictionaryWithObject:@"http://localhost/OrdersAPI"
                                                  forKey:CPHTTPStoreBaseURL];
    var store  = [[CPHTTPStore alloc] initWithStoreID:@"test2" configuration:storeConfig];
    var coordinator = [[CPPersistentStoreCoordinator alloc]
                            initWithManagedObjectModel:model
                                             storeType:[CPHTTPStoreType class]
                                    storeConfiguration:storeConfig];
    [store setStoreCoordinator:coordinator];

    var orderObj = [orderEntity createObject];
    var orderID  = [[CPManagedObjectID alloc] initWithEntity:orderEntity
                                                    globalID:@"Order|orderID=2;"
                                                 isTemporary:NO];
    [orderObj setObjectID:orderID];
    [orderObj setFault:NO];

    var expObj = [expEntity createObject];
    var expID  = [[CPManagedObjectID alloc] initWithEntity:expEntity
                                                  globalID:@"OrderExpense|expenseID=9;"
                                               isTemporary:NO];
    [expObj setObjectID:expID];
    [expObj setFault:NO];

    var allMaterialized = [CPMutableDictionary dictionaryWithObjectsAndKeys:
                               orderObj, @"Order|orderID=2;",
                               expObj,   @"OrderExpense|expenseID=9;"];

    // Apply the to-one from expense's perspective:
    //   relationships: { order: {entity:"Order", pk:{orderID:2}} }
    var relationships = {
        order: { entity: "Order", pk: { orderID: 2 } }
    };

    [store _applyRelationships:relationships
                      toObject:expObj
               allMaterialized:allMaterialized
                       context:nil];

    // expense.order should be set
    var orderVal = [[expObj data] objectForKey:@"order"];
    [self assertNotNull:orderVal
                message:@"expense.order should be non-nil after _applyRelationships:"];

    // Inverse: Order.expenses should now include the expense's objectID
    var expensesSet = [[orderObj data] objectForKey:@"expenses"];
    [self assertNotNull:expensesSet
                message:@"Order.expenses should be non-nil after inverse propagation"];
    [self assert:1 equals:[expensesSet count]
         message:@"Order.expenses should contain exactly one entry after inverse propagation"];
}


// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

- (CPHTTPStore)_makeStore
{
    var config = [CPDictionary dictionaryWithObject:@"http://localhost/OrdersAPI"
                                             forKey:CPHTTPStoreBaseURL];
    return [[CPHTTPStore alloc] initWithStoreID:@"test" configuration:config];
}

@end
