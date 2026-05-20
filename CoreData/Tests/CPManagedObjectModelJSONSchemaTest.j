@import <OJUnit/OJTestCase.j>

@import "CoreData.j"

var path = require("path");

@implementation CPManagedObjectModelJSONSchemaTest : OJTestCase
{
}

-(void)testInitWithoutSchema
{
    var schemas = [CPDictionary dictionary];
    var model = [CPManagedObjectModel modelWithJSONSchemaURLs:schemas
                                                        named:"test"];
    [self assertNotNull:model];
}


-(void)testInitWithSchemaFromURL
{
    var urlBase = path.join(path.dirname(__filename), "data");
    var schemas = [[CPMutableDictionary alloc] init];
    [schemas setObject:path.join(urlBase, "schema1.json") forKey:"Application"];
    [schemas setObject:path.join(urlBase, "schema2.json") forKey:"Contract"];
    var model = [CPManagedObjectModel modelWithJSONSchemaURLs:schemas
                                                        named:"schema?"];
    [self assertNotNull:model];
    var entity = [model entityWithName:"Application"];
    [self assertNotNull:entity
                message:"Entity \"Application\" not found in model!"];
    [self assert:"kind, id, name, created, subschema, periods"
          equals:[entity propertyNames].join(", ")];
    var attr;
    var attrs = [entity attributesByName];
    attr = [attrs valueForKey:"created"];
    [self assert:"sl:rfc3339"
          equals:[attr valueTransformerName]];
    var entity = [model entityWithName:"Contract"];
    [self assertNotNull:entity
                message:"Entity \"Contract\" not found in model!"];
    [self assert:"kind, periods, created, contractor, id, name"
          equals:[entity propertyNames].join(", ")];
}


-(void)testSubschema
{
    var urlBase = path.join(path.dirname(__filename), "data");
    var schemas = [[CPMutableDictionary alloc] init];
    [schemas setObject:path.join(urlBase, "schema1.json") forKey:"Application"];
    var model = [CPManagedObjectModel modelWithJSONSchemaURLs:schemas
                                                        named:"schema?"];
    [self assertNotNull:model];
    var entity = [model entityWithName:"Application"];
    [self assertNotNull:entity
                message:"Entity \"Application\" not found in model!"];
    var sub = [entity subentityWithName:"subschema"];
    [self assertNotNull:sub
                message:"Subentity \"subschema\" not found!"];
    var sub = [entity subentityWithName:"periods"];
    [self assertNotNull:sub
                message:"Subentity for periods array not found!"];
    var attr;
    var attrs = [entity attributesByName];
    attr = [attrs valueForKey:"subschema"];
    [self assert:"CoreDataJSONSchema_object"
          equals:[attr valueTransformerName]];
}

@end
