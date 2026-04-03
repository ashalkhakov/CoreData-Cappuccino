@import <OJUnit/OJTestCase.j>

@import "Tools.j"


@implementation CPEntityDescriptionExtendedTest : OJTestCase
{
    CPEntityDescription entity;
    CPManagedObjectContext context;
}

-(void)setUp
{
    entity = [[CPEntityDescription alloc] init];
    [entity setName:"ExtTestEntity"];
    [entity addAttributeWithName:"title"
                      classValue:"CPString"
                      typeValue:CPDStringAttributeType
                       optional:YES];
    [entity addRelationshipWithName:"children"
                             toMany:YES
                           optional:YES
                         deleteRule:CPRelationshipDescriptionDeleteRuleNullify
                        destination:"ExtTestEntity"];
    context = [Tools testContextWithModel:nil storeType:nil];
}

-(void)testEntityWithNameReturnsKnownEntity
{
    var entity1 = [CPEntityDescription entityWithName:"Testentity"
                               inManagedObjectContext:context];
    [self assertNotNull:entity1
                message:"entityWithName:inManagedObjectContext: should return entity for known name"];
    [self assert:"Testentity"
          equals:[entity1 name]
         message:"Returned entity should have the correct name"];
}

-(void)testEntityWithNameReturnsNilForUnknown
{
    var result = [CPEntityDescription entityWithName:"NoSuchEntity"
                              inManagedObjectContext:context];
    [self assertNull:result
             message:"entityWithName:inManagedObjectContext: should return nil for unknown name"];
}

-(void)testEntityName
{
    [self assert:"ExtTestEntity"
          equals:[entity name]
         message:"[entity name] should return the name set on it"];
}

-(void)testEntityPropertiesCount
{
    [self assert:2
          equals:[[entity properties] count]
         message:"[entity properties] should contain all added properties"];
}

-(void)testAttributesByName
{
    var attrs = [entity attributesByName];
    [self assertNotNull:[attrs objectForKey:"title"]
                message:"attributesByName should contain the 'title' attribute"];
}

-(void)testRelationshipsByName
{
    var rels = [entity relationshipsByName];
    [self assertNotNull:[rels objectForKey:"children"]
                message:"relationshipsByName should contain the 'children' relationship"];
}

-(void)testAddSamePropertyObjectTwiceNoDoubling
{
    var entity2 = [[CPEntityDescription alloc] init];
    [entity2 setName:"DupeTestEntity"];
    var attr = [[CPAttributeDescription alloc] init];
    [attr setName:"dupeAttr"];
    [attr setTypeValue:CPDStringAttributeType];
    [attr setClassValue:"CPString"];
    [attr setIsOptional:YES];
    [entity2 addProperty:attr];
    [entity2 addProperty:attr];
    [self assert:1
          equals:[[entity2 properties] count]
         message:"Adding the same property object twice should not duplicate it"];
}

-(void)testIsAttributeNameYes
{
    [self assertTrue:[entity isAttributeName:"title"]
             message:"isAttributeName: should return YES for an attribute"];
}

-(void)testIsAttributeNameNoForRelationship
{
    [self assertFalse:[entity isAttributeName:"children"]
              message:"isAttributeName: should return NO for a relationship"];
}

-(void)testIsRelationshipNameYes
{
    [self assertTrue:[entity isRelationshipName:"children"]
             message:"isRelationshipName: should return YES for a relationship"];
}

-(void)testIsRelationshipNameNoForAttribute
{
    [self assertFalse:[entity isRelationshipName:"title"]
              message:"isRelationshipName: should return NO for an attribute"];
}

@end
