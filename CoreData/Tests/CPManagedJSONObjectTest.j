
@import <OJUnit/OJTestCase.j>

@import "Tools.j"

var path = require("path");

@implementation CPManagedJSONObjectTest : OJTestCase
{
    CPManagedObjectModel model;
    CPManagedObjectContext context;
    CPManagedObject original;
}

-(void)setUp
{
    var urlBase = path.join(path.dirname(__filename), "data");
    var schemas = [[CPMutableDictionary alloc] init];
    [schemas setObject:path.join(urlBase, "mo_schema1.json") forKey:"Type1"];
    model = [CPManagedObjectModel modelWithJSONSchemaURLs:schemas
                                                    named:"testschema"];
    context = [Tools testContextWithModel:model storeType:nil];
    var entity = [model entityWithName:"Type1"];
    original = [entity createObject];
}

-(void)testDoNotCloneLocalID
{
    var objectID = [original objectID];
    var clone = [original clone];
    [self assertTrue:[[original objectID] localID] != [[clone objectID] localID]];
}

-(void)testCloneGlobalID
{
    var objectID = [original objectID];
    [objectID setGlobalID:"myGlobalID"];
    var clone = [original clone];
    [self assertNotNull:clone];
    [self assert:"myGlobalID"
          equals:[[clone objectID] globalID]];
}

-(void)testCloneData
{
    [original setJSONObject:{"string1":"Name"}];
    var clone = [original clone];
    [self assertNotNull:clone];
    [self assert:"Name"
          equals:[clone valueForKey:"string1"]];
}

-(void)testSerializeAsDict
{
    var serialized = [original serializeToDictionary:YES
                           containsChangedProperties:NO];
    [self assertNotNull:serialized];

    [self assertNull:[[serialized valueForKey:CPManagedObjectIDKey] valueForKey:"CPglobalID"]];
    [self assertNotNull:[[serialized valueForKey:CPManagedObjectIDKey] valueForKey:"CPlocalID"]];
    [self assertTrue:[[serialized valueForKey:CPManagedObjectIDKey] valueForKey:"CPisTemporaryID"]];
    [self assert:"Type1"
          equals:[[serialized valueForKey:CPManagedObjectIDKey] valueForKey:"CPEntityDescriptionName"]];
    [self assert:"Type1"
          equals:[serialized valueForKey:CPEntityDescriptionName]];
    [self assertFalse:[serialized valueForKey:CPisFault]];
    [self assertFalse:[serialized valueForKey:CPisUpdated]];
    [self assertFalse:[serialized valueForKey:CPisDeleted]];
    [self assert:"testschema"
          equals:[serialized valueForKey:CPmodelName]];

    [self assert:"{\"string1\":\"default for string1\",\"enum1\":\"tomorrow\",\"object1\":{\"attr1\":\"default for attr1\",\"transform\":\"untransformed\"},\"array1\":[]}"
          equals:[serialized valueForKey:CPallProperties]];
}

-(void)testDeserializeAsDict
{
    var serialized = [original serializeToDictionary:YES
                           containsChangedProperties:NO];
    var obj = [CPManagedObject deserializeFromDictionary:serialized
                                             withContext:context];
    [self assert:"{\"string1\":\"default for string1\",\"enum1\":\"tomorrow\",\"object1\":{\"attr1\":\"default for attr1\",\"transform\":\"untransformed\"},\"array1\":[]}"
          equals:[[CPData dataWithJSONObject:[obj JSONObject]] rawString]];
};

-(void)testSerializeAsNList
{
    var serialized = [original serializeTo280NPLIST:YES
                           containsChangedProperties:NO];
    [self assertNotNull:serialized];
}

@end

