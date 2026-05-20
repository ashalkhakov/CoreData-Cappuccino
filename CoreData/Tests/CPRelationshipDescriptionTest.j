@import <OJUnit/OJTestCase.j>

@import "Tools.j"


@implementation CPRelationshipDescriptionTest : OJTestCase

-(void)testIsToManyYes
{
    var rel = [[CPRelationshipDescription alloc] init];
    [rel setName:"children"];
    [rel setIsToMany:YES];
    [self assertTrue:[rel isToMany]
             message:"isToMany should return YES for a to-many relationship"];
}

-(void)testIsToManyNo
{
    var rel = [[CPRelationshipDescription alloc] init];
    [rel setName:"parent"];
    [rel setIsToMany:NO];
    [self assertFalse:[rel isToMany]
              message:"isToMany should return NO for a to-one relationship"];
}

-(void)testNameRoundTrip
{
    var rel = [[CPRelationshipDescription alloc] init];
    [rel setName:"items"];
    [self assert:"items"
          equals:[rel name]
         message:"name should return the name set on the relationship"];
}

-(void)testDestinationEntityNameRoundTrip
{
    var rel = [[CPRelationshipDescription alloc] init];
    [rel setDestinationEntityName:"Order"];
    [self assert:"Order"
          equals:[rel destinationEntityName]
         message:"destinationEntityName should return the correct entity name"];
}

-(void)testDeleteRuleDefaultIsNullify
{
    var rel = [[CPRelationshipDescription alloc] init];
    [self assert:CPRelationshipDescriptionDeleteRuleNullify
          equals:[rel deleteRule]
         message:"Default delete rule should be Nullify (0)"];
}

-(void)testDeleteRuleNullify
{
    var rel = [[CPRelationshipDescription alloc] init];
    [rel setDeleteRule:CPRelationshipDescriptionDeleteRuleNullify];
    [self assert:CPRelationshipDescriptionDeleteRuleNullify
          equals:[rel deleteRule]
         message:"deleteRule should round-trip for Nullify"];
}

-(void)testDeleteRuleCascade
{
    var rel = [[CPRelationshipDescription alloc] init];
    [rel setDeleteRule:CPRelationshipDescriptionDeleteRuleCascade];
    [self assert:CPRelationshipDescriptionDeleteRuleCascade
          equals:[rel deleteRule]
         message:"deleteRule should round-trip for Cascade"];
}

-(void)testDeleteRuleDeny
{
    var rel = [[CPRelationshipDescription alloc] init];
    [rel setDeleteRule:CPRelationshipDescriptionDeleteRuleDeny];
    [self assert:CPRelationshipDescriptionDeleteRuleDeny
          equals:[rel deleteRule]
         message:"deleteRule should round-trip for Deny"];
}

-(void)testDeleteRuleNoAction
{
    var rel = [[CPRelationshipDescription alloc] init];
    [rel setDeleteRule:CPRelationshipDescriptionDeleteRuleNoAction];
    [self assert:CPRelationshipDescriptionDeleteRuleNoAction
          equals:[rel deleteRule]
         message:"deleteRule should round-trip for NoAction"];
}

@end
