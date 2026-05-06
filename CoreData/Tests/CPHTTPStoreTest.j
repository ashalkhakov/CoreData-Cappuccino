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

- (void)testGlobalIDStringTempID
{
    // Plain JS-object temp ID (as parsed from a server JSON response)
    var store    = [self _makeStore],
        serverID = {"temp": "invoice-0"};

    [self assert:@"temp:invoice-0"
          equals:[store _globalIDStringForServerID:serverID]
         message:@"temp ID should map to 'temp:<key>'"];
}

- (void)testGlobalIDStringTempIDObjJDict
{
    // ObjJ dictionary temp ID (as might be constructed in client code)
    var store    = [self _makeStore],
        serverID = @{ @"temp": @"item-1" };

    [self assert:@"temp:item-1"
          equals:[store _globalIDStringForServerID:serverID]
         message:@"ObjJ-dict temp ID should map to 'temp:<key>'"];
}

/*!
    Verifies that a server response that uses temp IDs (isProposal:true) is
    materialised correctly:
    – Each object in objectsByID gets its own unique CPManagedObject (not a
      single collision object shared by all three).
    – Only root objects are present in the root list; prefetched relationship
      targets (lineItems) are NOT promoted to root results.

    This is a regression test for the bug where _globalIDStringForServerID:
    returned "|" for every temp ID, causing all three objects to collide on
    the same globalID in the context registry, and the same merged object to
    appear 3 times in the result.
*/
- (void)testFetchMaterialisationWithTempIDs_rootObjectsDistinctFromPrefetched
{
    // Build a minimal model with Invoice and InvoiceLineItem entities
    var store  = [self _makeStore],
        model  = [[CPManagedObjectModel alloc] init];

    var invoiceEntity = [[CPEntityDescription alloc] init];
    [invoiceEntity setName:@"Invoice"];
    [invoiceEntity addAttributeWithName:@"status"   classValue:@"CPString" typeValue:CPDStringAttributeType optional:YES];
    [invoiceEntity addAttributeWithName:@"dueDate"  classValue:@"CPString" typeValue:CPDStringAttributeType optional:YES];
    [invoiceEntity addRelationshipWithName:@"lineItems" toMany:YES  optional:YES deleteRule:0 destination:@"InvoiceLineItem"];

    var lineItemEntity = [[CPEntityDescription alloc] init];
    [lineItemEntity setName:@"InvoiceLineItem"];
    [lineItemEntity addAttributeWithName:@"lineDescription" classValue:@"CPString" typeValue:CPDStringAttributeType optional:YES];
    [lineItemEntity addAttributeWithName:@"quantity"        classValue:@"CPNumber" typeValue:CPDInteger32AttributeType optional:YES];
    [lineItemEntity addRelationshipWithName:@"invoice" toMany:NO optional:YES deleteRule:0 destination:@"Invoice"];

    [model addEntity:invoiceEntity];
    [model addEntity:lineItemEntity];

    // Simulate the proposal server response (objectsByID uses "temp:X" keys)
    var invoiceServerObj = {
        "entity": "Invoice",
        "id": {"temp": "invoice-0"},
        "values": {"status": "draft", "dueDate": "2026-06-05"},
        "relationships": {
            "lineItems": [{"temp": "item-0"}, {"temp": "item-1"}]
        }
    };
    var item0ServerObj = {
        "entity": "InvoiceLineItem",
        "id": {"temp": "item-0"},
        "values": {"lineDescription": "sku1", "quantity": 45},
        "relationships": {}
    };
    var item1ServerObj = {
        "entity": "InvoiceLineItem",
        "id": {"temp": "item-1"},
        "values": {"lineDescription": "sku2", "quantity": 5},
        "relationships": {}
    };

    var coordinator = [[CPPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [store setStoreCoordinator:coordinator];
    [coordinator setPersistentStore:store];
    var context = [[CPManagedObjectContext alloc] initWithPersistentStoreCoordinator:coordinator];

    // First pass: materialise all objects
    var allMaterialized = [[CPMutableDictionary alloc] init];
    var objects = {
        "temp:invoice-0": invoiceServerObj,
        "temp:item-0":    item0ServerObj,
        "temp:item-1":    item1ServerObj
    };

    for (var key in objects)
    {
        if (!objects.hasOwnProperty(key)) continue;
        var matObj = [store _materializeServerObject:objects[key] context:context];
        if (matObj !== nil)
            [allMaterialized setObject:matObj forKey:key];
    }

    // Verify: each entry in allMaterialized is a distinct object with the
    // correct entity and a unique globalID.
    [self assert:3 equals:[allMaterialized count]
         message:@"all three server objects should materialise to distinct managed objects"];

    var invoiceMat = [allMaterialized objectForKey:@"temp:invoice-0"],
        item0Mat   = [allMaterialized objectForKey:@"temp:item-0"],
        item1Mat   = [allMaterialized objectForKey:@"temp:item-1"];

    [self assertNotNull:invoiceMat message:@"invoice object should be in allMaterialized"];
    [self assertNotNull:item0Mat   message:@"item-0 object should be in allMaterialized"];
    [self assertNotNull:item1Mat   message:@"item-1 object should be in allMaterialized"];

    [self assert:@"Invoice"         equals:[[invoiceMat entity] name] message:@"invoice entity name"];
    [self assert:@"InvoiceLineItem" equals:[[item0Mat   entity] name] message:@"item-0 entity name"];
    [self assert:@"InvoiceLineItem" equals:[[item1Mat   entity] name] message:@"item-1 entity name"];

    [self assert:@"temp:invoice-0" equals:[[invoiceMat objectID] globalID] message:@"invoice globalID"];
    [self assert:@"temp:item-0"    equals:[[item0Mat   objectID] globalID] message:@"item-0 globalID"];
    [self assert:@"temp:item-1"    equals:[[item1Mat   objectID] globalID] message:@"item-1 globalID"];

    // Verify root filtering: only Invoice is a root object
    var rootIDs     = [{"temp": "invoice-0"}],
        resultArray = [[CPMutableArray alloc] init],
        inRoot      = [[CPMutableSet alloc] init];

    for (var i = 0; i < rootIDs.length; i++)
    {
        var rootKey = [store _globalIDStringForServerID:rootIDs[i]];
        var rootObj = [allMaterialized objectForKey:rootKey];
        if (rootObj !== nil)
        {
            [resultArray addObject:rootObj];
            [inRoot addObject:rootObj];
        }
    }
    var matEnum = [allMaterialized objectEnumerator];
    var matObj;
    while ((matObj = [matEnum nextObject]))
    {
        if (![inRoot containsObject:matObj])
            [resultArray addObject:matObj];
    }

    [self assert:3 equals:[resultArray count]
         message:@"resultArray should have 3 items total (1 root + 2 prefetched)"];
    [self assertSame:invoiceMat equals:[resultArray objectAtIndex:0]
             message:@"the first (root) result must be the Invoice object"];
}

- (void)testGlobalIDRoundTripToServerID
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
    var kOrderID   = 1,
        kExpenseID = 7;

    var orderObj = [orderEntity createObject];
    var orderID  = [[CPManagedObjectID alloc] initWithEntity:orderEntity
                                                    globalID:@"Order|orderID=" + kOrderID + @";"
                                                 isTemporary:NO];
    [orderObj setObjectID:orderID];
    [orderObj setFault:NO];

    var expObj = [expEntity createObject];
    var expID  = [[CPManagedObjectID alloc] initWithEntity:expEntity
                                                  globalID:@"OrderExpense|expenseID=" + kExpenseID + @";"
                                               isTemporary:NO];
    [expObj setObjectID:expID];
    [expObj setFault:NO];

    // allMaterialized maps globalID → managed object
    var allMaterialized = [CPMutableDictionary dictionaryWithObjectsAndKeys:
                               orderObj, [orderID globalID],
                               expObj,   [expID globalID]];

    // ---- Apply relationships: Order.expenses = [expense #kExpenseID] ----
    // Simulate the server returning:
    //   relationships: { expenses: [{entity:"OrderExpense", pk:{expenseID:kExpenseID}}] }
    // The server does NOT include `order` in the expense's relationships block.
    var relationships = {
        expenses: [{ entity: "OrderExpense", pk: { expenseID: kExpenseID } }]
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
    [self assert:[orderID globalID] equals:[orderVal globalID]
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

    var kOrderID2   = 2,
        kExpenseID2 = 9;

    var orderObj = [orderEntity createObject];
    var orderID  = [[CPManagedObjectID alloc] initWithEntity:orderEntity
                                                    globalID:@"Order|orderID=" + kOrderID2 + @";"
                                                 isTemporary:NO];
    [orderObj setObjectID:orderID];
    [orderObj setFault:NO];

    var expObj = [expEntity createObject];
    var expID  = [[CPManagedObjectID alloc] initWithEntity:expEntity
                                                  globalID:@"OrderExpense|expenseID=" + kExpenseID2 + @";"
                                               isTemporary:NO];
    [expObj setObjectID:expID];
    [expObj setFault:NO];

    var allMaterialized = [CPMutableDictionary dictionaryWithObjectsAndKeys:
                               orderObj, [orderID globalID],
                               expObj,   [expID globalID]];

    // Apply the to-one from expense's perspective:
    //   relationships: { order: {entity:"Order", pk:{orderID:kOrderID2}} }
    var relationships = {
        order: { entity: "Order", pk: { orderID: kOrderID2 } }
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
// CPHTTPStore – obtainPermanentIDsForObjects:error:
// ---------------------------------------------------------------------------

/*!
    Verifies that obtainPermanentIDsForObjects:error: promotes the temporary
    IDs of newly-inserted objects to permanent placeholders (isTemporary=NO)
    without requiring a server round-trip, and that the localID (used as the
    temp key for the cdSave payload) is preserved.
*/
- (void)testObtainPermanentIDsForObjects_promotesTemporaryIDs
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Customer"];

    // Create two objects with temporary IDs (simulating insertNewObjectForEntityForName:)
    var obj1 = [[CPManagedObject alloc] init];
    var id1  = [[CPManagedObjectID alloc] initWithEntity:entity
                                                globalID:nil
                                             isTemporary:YES];
    [obj1 setObjectID:id1];

    var obj2 = [[CPManagedObject alloc] init];
    var id2  = [[CPManagedObjectID alloc] initWithEntity:entity
                                                globalID:nil
                                             isTemporary:YES];
    [obj2 setObjectID:id2];

    [self assertTrue:[[obj1 objectID] isTemporary]
             message:@"precondition: obj1 should start with a temporary ID"];
    [self assertTrue:[[obj2 objectID] isTemporary]
             message:@"precondition: obj2 should start with a temporary ID"];

    var localID1 = [id1 localID],
        localID2 = [id2 localID];

    var objects = [CPSet setWithObjects:obj1, obj2, nil];
    var error   = nil;
    var result  = [store obtainPermanentIDsForObjects:objects error:@ref(error)];

    [self assertTrue:result
             message:@"obtainPermanentIDsForObjects:error: should return YES"];
    [self assertFalse:[[obj1 objectID] isTemporary]
              message:@"obj1 ID should no longer be temporary after obtainPermanentIDsForObjects:"];
    [self assertFalse:[[obj2 objectID] isTemporary]
              message:@"obj2 ID should no longer be temporary after obtainPermanentIDsForObjects:"];

    // localID must be preserved so that _tempKeyForObject: keeps working
    [self assert:localID1 equals:[[obj1 objectID] localID]
         message:@"localID of obj1 must be unchanged after obtainPermanentIDsForObjects:"];
    [self assert:localID2 equals:[[obj2 objectID] localID]
         message:@"localID of obj2 must be unchanged after obtainPermanentIDsForObjects:"];

    // globalID is still nil; the server has not responded yet
    [self assertFalse:[[obj1 objectID] validatedGlobalID]
              message:@"globalID of obj1 should still be nil (set later from idMap)"];
}

/*!
    Verifies that _refForObjectID: falls back to the temp-key encoding when
    globalID is nil even if isTemporary was already cleared.  This is needed
    when an inserted object references another co-inserted object via a
    relationship: both have permanent-placeholder IDs but neither has a server
    ID yet.
*/
- (void)testRefForObjectID_usesTemKeyWhenGlobalIDNil
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Order"];

    var objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                 globalID:nil
                                              isTemporary:YES];
    // Simulate obtainPermanentIDsForObjects: clearing isTemporary
    [objID setIsTemporary:NO];

    [self assertFalse:[objID isTemporary]
              message:@"precondition: isTemporary should be NO"];
    [self assertFalse:[objID validatedGlobalID]
              message:@"precondition: globalID should still be nil"];

    var ref = [store _refForObjectID:objID];
    [self assertNotNull:ref
                message:@"_refForObjectID: should return a non-nil dictionary"];
    [self assertNotNull:[ref objectForKey:@"temp"]
                message:@"_refForObjectID: should use temp key when globalID is nil"];
    [self assertNull:[ref objectForKey:@"entity"]
             message:@"_refForObjectID: should NOT produce a server-ID dict when globalID is nil"];
}


// ---------------------------------------------------------------------------
// CPHTTPStore – _encodeObjectForUpdate: changed-data-only and empty-payload filter
// ---------------------------------------------------------------------------

/*!
    Verifies that _encodeObjectForUpdate: encodes only the fields that appear
    in the object's _changedData, not the entire _data dictionary.

    Scenario: a Product was fetched from the server (so _data has many fields),
    but the user only changed "name". The update payload must contain only
    "name" in the values dict, not all other fields like "sku", "unitPrice" etc.
*/
- (void)testEncodeObjectForUpdate_onlySendsChangedFields
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Product"];
    [entity addAttributeWithName:@"productID"  classValue:@"CPNumber" typeValue:CPDInteger32AttributeType optional:NO];
    [entity addAttributeWithName:@"name"        classValue:@"CPString" typeValue:CPDStringAttributeType    optional:NO];
    [entity addAttributeWithName:@"sku"         classValue:@"CPString" typeValue:CPDStringAttributeType    optional:YES];
    [entity addAttributeWithName:@"unitPrice"   classValue:@"CPNumber" typeValue:CPDInteger32AttributeType optional:YES];

    var obj   = [entity createObject],
        objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                 globalID:@"Product|productID=508;"
                                              isTemporary:NO];
    [obj setObjectID:objID];
    [obj setFault:NO];

    // Simulate "fetched from server" — all fields are in _data
    var fullData = [CPMutableDictionary dictionaryWithObjectsAndKeys:
                        508,         @"productID",
                        @"Gadget B", @"name",
                        @"GADGET-B", @"sku",
                        26,          @"unitPrice"];
    [obj _setData:fullData];

    // User only changed "name"
    var changedData = [CPMutableDictionary dictionaryWithObject:@"Gadget B v2" forKey:@"name"];
    [obj _setChangedData:changedData];

    var encoded = [store _encodeObjectForUpdate:obj];

    [self assertNotNull:encoded
                message:@"_encodeObjectForUpdate: should produce a non-nil dict for a changed object"];

    var values = [encoded objectForKey:@"values"];
    [self assertNotNull:values
                message:@"encoded result should have a 'values' key"];
    [self assert:1 equals:[values count]
         message:@"only 1 attribute should be encoded (only 'name' was changed)"];
    [self assert:@"Gadget B v2" equals:[values objectForKey:@"name"]
         message:@"the changed 'name' value should be encoded"];
    [self assertNull:[values objectForKey:@"sku"]
             message:@"unchanged 'sku' should NOT be encoded"];
    [self assertNull:[values objectForKey:@"unitPrice"]
             message:@"unchanged 'unitPrice' should NOT be encoded"];
    [self assertNull:[values objectForKey:@"productID"]
             message:@"unchanged 'productID' should NOT be encoded"];
}

/*!
    Verifies that _encodeObjectForUpdate: returns nil when the only
    _changedData entries are inverse to-many relationships that were never
    loaded from the server.

    Scenario: a Product is fetched in the main context.  Later, a new
    OrderLineItem is inserted with lineItem.product = product.  The framework's
    inverse-relationship maintenance adds the lineItem's objectID to
    product._changedData["lineItems"], but lineItems was never fetched
    (isRelationshipLoaded:NO).  The product should NOT appear in the update
    payload.
*/
- (void)testEncodeObjectForUpdate_returnsNilWhenOnlyUnloadedInverseRelChanged
{
    var store  = [self _makeStore],
        entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Product"];
    [entity addAttributeWithName:@"productID" classValue:@"CPNumber" typeValue:CPDInteger32AttributeType optional:NO];
    [entity addRelationshipWithName:@"lineItems"
                             toMany:YES
                           optional:YES
                         deleteRule:0
                        destination:@"OrderLineItem"];

    var obj   = [entity createObject],
        objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                 globalID:@"Product|productID=508;"
                                              isTemporary:NO];
    [obj setObjectID:objID];
    [obj setFault:NO];

    // Simulate "fetched from server" — scalar data is in _data; lineItems NOT loaded
    var fullData = [CPMutableDictionary dictionaryWithObject:508 forKey:@"productID"];
    [obj _setData:fullData];

    // Inverse maintenance put a lineItem ID into _changedData["lineItems"],
    // but the lineItems relationship was never loaded from the server.
    var lineItemID = [[CPManagedObjectID alloc] initWithEntity:nil
                                                      globalID:nil
                                                   isTemporary:YES];
    var changedSet = [CPMutableSet setWithObject:lineItemID];
    var changedData = [CPMutableDictionary dictionaryWithObject:changedSet forKey:@"lineItems"];
    [obj _setChangedData:changedData];

    // lineItems was NOT loaded from the server — isRelationshipLoaded returns NO
    [self assertFalse:[obj isRelationshipLoaded:@"lineItems"]
              message:@"precondition: lineItems should not be marked as loaded"];

    var encoded = [store _encodeObjectForUpdate:obj];

    [self assertNull:encoded
             message:@"_encodeObjectForUpdate: should return nil when the only changed "
                    + @"data is an inverse to-many that was never loaded from the server"];
}

/*!
    Verifies that _encodeObjectForUpdate: omits attributes whose value in
    _changedData matches the coordinator row-cache baseline (i.e. the value
    was re-set by UI bindings to the same thing it already was, not actually
    edited by the user).

    Scenario: an Address is fetched from the server; a form opens and UI
    bindings call setValue:forKey: for every bound field — setting them to the
    same values already stored.  All attributes end up in _changedData, but
    none differ from the coordinator cache.  The Address must NOT appear in the
    update payload.
*/
- (void)testEncodeObjectForUpdate_skipsAttributesUnchangedFromBaseline
{
    // Build a store wired to a coordinator so cacheRowData: is reachable
    var config      = [CPDictionary dictionaryWithObject:@"http://localhost/OrdersAPI"
                                                  forKey:CPHTTPStoreBaseURL],
        store       = [[CPHTTPStore alloc] initWithStoreID:@"test" configuration:config],
        coordinator = [[CPPersistentStoreCoordinator alloc] init];
    [store setStoreCoordinator:coordinator];

    var entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Address"];
    [entity addAttributeWithName:@"addressID" classValue:@"CPNumber" typeValue:CPDInteger32AttributeType optional:NO];
    [entity addAttributeWithName:@"street1"   classValue:@"CPString" typeValue:CPDStringAttributeType    optional:YES];
    [entity addAttributeWithName:@"city"      classValue:@"CPString" typeValue:CPDStringAttributeType    optional:YES];

    var globalID = @"Address|addressID=482;",
        obj   = [entity createObject],
        objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                 globalID:globalID
                                              isTemporary:NO];
    [obj setObjectID:objID];
    [obj setFault:NO];

    // Simulate server fetch: _data has all fields
    var serverData = [CPMutableDictionary dictionaryWithObjectsAndKeys:
                          482,          @"addressID",
                          @"42 Oak Ave", @"street1",
                          @"Shelbyville", @"city"];
    [obj _setData:serverData];

    // Coordinator row-cache holds the same data (set when the object was fetched)
    [coordinator cacheRowData:serverData forGlobalID:globalID];

    // UI bindings re-set all fields to the same values — this fills _changedData
    // with values identical to the server state.
    var changedData = [CPMutableDictionary dictionaryWithObjectsAndKeys:
                           482,           @"addressID",
                           @"42 Oak Ave", @"street1",
                           @"Shelbyville", @"city"];
    [obj _setChangedData:changedData];

    var encoded = [store _encodeObjectForUpdate:obj];

    [self assertNull:encoded
             message:@"_encodeObjectForUpdate: should return nil when all _changedData "
                    + @"values match the coordinator row-cache baseline"];
}

/*!
    Verifies that _encodeObjectForUpdate: includes only the attribute that was
    GENUINELY changed, even when _changedData also contains other attributes
    that were re-set to their existing (baseline) values.
*/
- (void)testEncodeObjectForUpdate_includesOnlyTrulyChangedAttributeWhenBaselinePresent
{
    var config      = [CPDictionary dictionaryWithObject:@"http://localhost/OrdersAPI"
                                                  forKey:CPHTTPStoreBaseURL],
        store       = [[CPHTTPStore alloc] initWithStoreID:@"test" configuration:config],
        coordinator = [[CPPersistentStoreCoordinator alloc] init];
    [store setStoreCoordinator:coordinator];

    var entity = [[CPEntityDescription alloc] init];
    [entity setName:@"Customer"];
    [entity addAttributeWithName:@"customerID" classValue:@"CPNumber" typeValue:CPDInteger32AttributeType optional:NO];
    [entity addAttributeWithName:@"fullName"   classValue:@"CPString" typeValue:CPDStringAttributeType    optional:NO];
    [entity addAttributeWithName:@"phone"      classValue:@"CPString" typeValue:CPDStringAttributeType    optional:YES];

    var globalID = @"Customer|customerID=1;",
        obj   = [entity createObject],
        objID = [[CPManagedObjectID alloc] initWithEntity:entity
                                                 globalID:globalID
                                              isTemporary:NO];
    [obj setObjectID:objID];
    [obj setFault:NO];

    var serverData = [CPMutableDictionary dictionaryWithObjectsAndKeys:
                          1,             @"customerID",
                          @"Alice",      @"fullName",
                          @"555-0100",   @"phone"];
    [obj _setData:serverData];
    [coordinator cacheRowData:serverData forGlobalID:globalID];

    // fullName was genuinely changed; phone and customerID were re-set to their
    // existing values by UI bindings.
    var changedData = [CPMutableDictionary dictionaryWithObjectsAndKeys:
                           1,          @"customerID",
                           @"Alice B.", @"fullName",
                           @"555-0100", @"phone"];
    [obj _setChangedData:changedData];

    var encoded = [store _encodeObjectForUpdate:obj];

    [self assertNotNull:encoded
                message:@"_encodeObjectForUpdate: should produce a non-nil result "
                       + @"when at least one attribute genuinely changed"];

    var values = [encoded objectForKey:@"values"];
    [self assert:1 equals:[values count]
         message:@"only the genuinely changed attribute should be encoded"];
    [self assert:@"Alice B." equals:[values objectForKey:@"fullName"]
         message:@"the changed 'fullName' should be encoded"];
    [self assertNull:[values objectForKey:@"phone"]
             message:@"'phone' was re-set to its baseline value and must be omitted"];
    [self assertNull:[values objectForKey:@"customerID"]
             message:@"'customerID' was re-set to its baseline value and must be omitted"];
}



- (CPHTTPStore)_makeStore
{
    var config = [CPDictionary dictionaryWithObject:@"http://localhost/OrdersAPI"
                                             forKey:CPHTTPStoreBaseURL];
    return [[CPHTTPStore alloc] initWithStoreID:@"test" configuration:config];
}

@end
