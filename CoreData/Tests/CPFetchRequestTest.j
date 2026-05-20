@import <OJUnit/OJTestCase.j>

@import "Tools.j"


@implementation CPFetchRequestTest : OJTestCase

-(void)testDefaultFetchLimit
{
    var req = [[CPFetchRequest alloc] init];
    [self assert:0
          equals:[req fetchLimit]
         message:"A new CPFetchRequest should have fetchLimit = 0"];
}

-(void)testDefaultFetchOffset
{
    var req = [[CPFetchRequest alloc] init];
    [self assert:0
          equals:[req fetchOffset]
         message:"A new CPFetchRequest should have fetchOffset = 0"];
}

-(void)testFetchLimitRoundTrip
{
    var req = [[CPFetchRequest alloc] init];
    [req setFetchLimit:25];
    [self assert:25
          equals:[req fetchLimit]
         message:"setFetchLimit:/fetchLimit should round-trip"];
}

-(void)testFetchOffsetRoundTrip
{
    var req = [[CPFetchRequest alloc] init];
    [req setFetchOffset:10];
    [self assert:10
          equals:[req fetchOffset]
         message:"setFetchOffset:/fetchOffset should round-trip"];
}

-(void)testPredicateRoundTrip
{
    var req = [[CPFetchRequest alloc] init];
    var pred = [CPDictionary dictionaryWithObject:"value" forKey:"key"];
    [req setPredicate:pred];
    [self assert:pred
          equals:[req predicate]
         message:"setPredicate:/predicate should round-trip"];
}

-(void)testEntityRoundTrip
{
    var req = [[CPFetchRequest alloc] init];
    var entity = [[CPEntityDescription alloc] init];
    [entity setName:"FetchTestEntity"];
    [req setEntity:entity];
    [self assert:entity
          equals:[req entity]
         message:"setEntity:/entity should round-trip"];
}

-(void)testSortDescriptorsRoundTrip
{
    var req = [[CPFetchRequest alloc] init];
    var sortDescriptors = [CPArray arrayWithObject:"sortByName"];
    [req setSortDescriptors:sortDescriptors];
    [self assert:sortDescriptors
          equals:[req sortDescriptors]
         message:"setSortDescriptors:/sortDescriptors should round-trip"];
}

@end
