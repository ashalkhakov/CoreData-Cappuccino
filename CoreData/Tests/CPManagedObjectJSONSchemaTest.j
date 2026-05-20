
@import <OJUnit/OJTestCase.j>

@import "CoreData.j"

var path = require("path");

@implementation CPManagedObjectJSONSchemaTest : OJTestCase
{
    CPManagedObjectModel model;
}

-(void)setUp
{
    var urlBase = path.join(path.dirname(__filename), "data");
    var schemas = [[CPMutableDictionary alloc] init];
    [schemas setObject:path.join(urlBase, "mo_schema1.json") forKey:"Type1"];
    model = [CPManagedObjectModel modelWithJSONSchemaURLs:schemas
                                                    named:"test"];
}

-(void)testCreateStringAttribute
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    [self assert:"default for string1"
          equals:[obj valueForKey:"string1"]]
    [obj setValue:"v1" forKey:"string1"];
    [self assert:"v1"
          equals:[obj valueForKey:"string1"]]
}

-(void)testCreateEnumAttribute
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    [self assert:"tomorrow"
          equals:[obj valueForKey:"enum1"]]
    [obj setValue:"today" forKey:"enum1"];
    [self assert:"today"
          equals:[obj valueForKey:"enum1"]]
}

-(void)testCreateObjectAttribute
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var obj1 = [obj valueForKey:"object1"];
    [self assertNotNull:obj1
                message:"Couldn't get value for \"object1\""];
    [self assert:"default for attr1"
          equals:[obj1 valueForKey:"attr1"]];
    [self assert:"default for attr1"
          equals:[obj valueForKeyPath:"object1.attr1"]];
}

-(void)testCreateArrayAttribute
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    [self assertTrue:[[obj valueForKey:"array1"] isKindOfClass:[CPArray class]]
             message:"Not an array!"]
    [obj setValue:[CPArray arrayWithObjects:"1", "2"] forKey:"array1"];
    [self assertTrue:[[obj valueForKey:"array1"] isKindOfClass:[CPArray class]]];
    [self assert:"1, 2"
          equals:[obj valueForKey:"array1"].join(', ')]
}

-(void)testSetJSONDataString
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var JSON = {"string1":"From JSON"};
    [obj setJSONObject:JSON];
    [self assert:"From JSON"
          equals:[obj valueForKey:"string1"]]
}

-(void)testSetJSONDataSubobject
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var JSON = {"string1":"From JSON",
                "object1":{"attr1":"attr1 from JSON"}
               };
    [obj setJSONObject:JSON];
    [self assert:[CPManagedJSONObject class]
          equals:[[obj valueForKey:"object1"] class]
         message:"Wrong class from subobject!"];
    [self assert:"attr1 from JSON"
          equals:[obj valueForKeyPath:"object1.attr1"]];
}

-(void)testSetAttributeSubobject
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    [[obj valueForKey:"object1"] setValue:"set" forKey:"attr1"];
    [self assert:"set"
          equals:[obj valueForKeyPath:"object1.attr1"]];
}

-(void)testInitializedSetAttributeSubsubobject
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    [[obj valueForKey:"object1"] setValue:[obj createObjectWithKeyPath:"object1.subobject"] forKey:"subobject"];
    [self assertNotNull:[[obj valueForKey:"object1"] valueForKey:"subobject"]];
    [[[obj valueForKey:"object1"] valueForKey:"subobject"] setValue:"set" forKey:"p1"];
    [self assert:"set"
          equals:[obj valueForKeyPath:"object1.subobject.p1"]];
}

-(void)testJSONSetAttributeSubsubobject
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var JSON = {"object1":{"subobject":{"p1":"json"}}};
    [obj setJSONObject:JSON];
    [self assertNotNull:[[obj valueForKey:"object1"] valueForKey:"subobject"]];
    [[[obj valueForKey:"object1"] valueForKey:"subobject"] setValue:"set" forKey:"p1"];
    [self assert:"set"
          equals:[obj valueForKeyPath:"object1.subobject.p1"]];
}

-(void)testJSONSetAttributeArraySubobject
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var JSON = {"array1":[{"subobject":{"p1":"json"}}]};
    [obj setJSONObject:JSON];
    [self assertNotNull:[obj valueForKey:"array1"][0]];
    [[[obj valueForKey:"array1"][0] valueForKey:"subobject"] setValue:"set" forKey:"p1"];
    [self assert:"set"
          equals:[[obj valueForKey:"array1"][0] valueForKeyPath:"subobject.p1"]];
}

-(void)testInitializedSetAttributeInnerArrayChange
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var arrayValue = [obj createObjectWithKeyPath:"array1"];
    [[obj valueForKey:"array1"] addObject:[obj createObjectWithKeyPath:"array1"]];
    [[obj valueForKey:"array1"][0] setValue:"a" forKey:"innerarray"];
    [self assert:"a"
          equals:[[obj valueForKey:"array1"][0] valueForKey:"innerarray"]];
}

-(void)testJSONSetAttributeInnerArrayChange
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var JSON = {"array1":[{}]};
    [obj setJSONObject:JSON];
    [[obj valueForKey:"array1"][0] setValue:"a" forKey:"innerarray"];
    [self assert:"a"
          equals:[[obj valueForKey:"array1"][0] valueForKeyPath:"innerarray"]];
}

-(void)testSetJSONDataMissingProperties
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var JSON = {};
    [obj setJSONObject:JSON];
    [self assertNull:[obj valueForKey:"missing"]
             message:"Expected null for missing string!"];
    [self assertTrue:[[obj valueForKey:"missingArray"] isKindOfClass:[CPArray class]]
         message:"Expected CPArray for missing array!"];
}

-(void)testCreateSubObject
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var object1 = [obj createObjectWithKeyPath:"object1"];
    [self assertNotNull:object1
                message:"Could not create object1!"];
    [self assert:obj
          equals:[object1 parentObject]
         message:"Wrong or no parent set!"];
    [self assert:"object1"
          equals:[object1 keyPath]
         message:"Wrong path!"];
    [self assert:"object1"
            equals:[[object1 entity] name]];
}

-(void)testCreateSubSubObject
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var subobject = [obj createObjectWithKeyPath:"object1.subobject"];
    [self assertNotNull:subobject
                message:"Could not create object1.subobject!"];
    [self assert:obj
          equals:[subobject parentObject]
         message:"Wrong or no parent set!"];
    [self assert:"object1.subobject"
          equals:[subobject keyPath]
         message:"Wrong path!"];
}

-(void)testCreateSubObjectForArray
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var object1 = [obj createObjectWithKeyPath:"array1"];
    [self assertNotNull:object1
                message:"Could not create object for array1!"];
    [self assert:obj
          equals:[object1 parentObject]
         message:"Wrong or no parent set for object in array1!"];
    [self assert:"array1"
          equals:[object1 keyPath]
         message:"Wrong path!"];
}

-(void)testCreateSubSubObjectForArray
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    var object1 = [obj createObjectWithKeyPath:"array1.subobject"];
    [self assertNotNull:object1
                message:"Could not create object!"];
    [self assert:obj
          equals:[object1 parentObject]
         message:"Wrong or no parent set for object in array1!"];
    [self assert:"array1.subobject"
          equals:[object1 keyPath]
         message:"Wrong path!"];
}

-(void)testGetJSONDataSubobject
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    [self assert:"{\"string1\":\"default for string1\",\"enum1\":\"tomorrow\",\"object1\":{\"attr1\":\"default for attr1\",\"transform\":\"untransformed\"},\"array1\":[]}"
          equals:[[CPData dataWithJSONObject:[obj JSONObject]] rawString]];
}

-(void)testTransformInSubobjectWithoutTransformer
{
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    [self assert:"untransformed"
          equals:[obj valueForKeyPath:"object1.transform"]]
    var arr = [obj valueForKey:"array1"];
    var d = [[entity subentityWithName:"array1"] createObject];
    [arr addObject:d];
    [self assert:"untransformed"
          equals:[[arr objectAtIndex:0] valueForKey:"transform"]];
}

-(void)testTransformInSubobjectWithTransformer
{
    [CPValueTransformer setValueTransformer:[[TestSimpleTransformer alloc] init]
                                    forName:@"TestTransformer"];
    var entity = [model entityWithName:"Type1"];
    var obj = [entity createObject];
    [self assert:"Transformed:untransformed"
          equals:[obj valueForKeyPath:"object1.transform"]]
    var arr = [obj valueForKey:"array1"];
    var d = [[entity subentityWithName:"array1"] createObject];
    [arr addObject:d];
    [self assert:"Transformed:untransformed"
          equals:[[arr objectAtIndex:0] valueForKey:"transform"]];
}

@end


@implementation TestSimpleTransformer : CPValueTransformer

+(BOOL)allowsReverseTransformation
{
    return YES;
}

- (id)reverseTransformedValue:(id)aValue
{
    return [CPString stringWithFormat:"Reverse:%@", aValue];
}

- (id)transformedValue:(id)aValue
{
    return [CPString stringWithFormat:"Transformed:%@", aValue];
}

@end

