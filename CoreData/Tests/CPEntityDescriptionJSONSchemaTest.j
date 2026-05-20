@import <OJUnit/OJTestCase.j>

@import "CoreData.j"

var path = require("path");
var fs = require("fs");
var _testDataDir = path.join(path.dirname(__filename), "data");

@implementation CPEntityDescriptionJSONSchemaTest : OJTestCase
{
    CPManagedObjectModel model;
}

-(void)setUp
{
    CPLog("dataDir = " + _testDataDir);
    CPLog("schema exists = " + fs.existsSync(path.join(_testDataDir, "mo_schema1.json")));
    var schemas = [[CPMutableDictionary alloc] init];
    [schemas setObject:path.join(_testDataDir, "mo_schema1.json") forKey:"Type1"];
    model = [CPManagedObjectModel modelWithJSONSchemaURLs:schemas named:"test"];
    CPLog("model = " + model);
}
/*
-(void)setUp
{
    var urlBase = path.join(path.dirname(__filename), "data");
    var schemas = [[CPMutableDictionary alloc] init];
    [schemas setObject:path.join(urlBase, "mo_schema1.json") forKey:"Type1"];
    model = [CPManagedObjectModel modelWithJSONSchemaURLs:schemas
                                                    named:"test"];
}*/

-(void)testCreateAttributeWithSubentities
{
    var entity = [model entityWithName:"Type1"];
    var prop = [entity createAttributeWithSubentityPath:"object1"];
    [self assertNotNull:prop
                message:"Got no property!"];
    [self assert:[CPManagedJSONObject class]
          equals:[prop class]
         message:"Wrong class!"];
    [self assert:"default for attr1"
          equals:[prop valueForKey:"attr1"]];
}

@end
