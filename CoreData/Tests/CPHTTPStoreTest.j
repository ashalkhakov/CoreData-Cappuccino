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
                   @"A",          @"value", nil];

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
    [req setPropertiesToFetch:[@"count"]];

    var body = [store _buildFetchBody:req];
    [self assert:@"count" equals:[body objectForKey:@"resultType"]];
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
        dict  = [CPDictionary dictionaryWithObjectsAndKeys:@"val", @"key", nil],
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
// Helper
// ---------------------------------------------------------------------------

- (CPHTTPStore)_makeStore
{
    var config = [CPDictionary dictionaryWithObject:@"http://localhost/OrdersAPI"
                                             forKey:CPHTTPStoreBaseURL];
    return [[CPHTTPStore alloc] initWithStoreID:@"test" configuration:config];
}

@end
