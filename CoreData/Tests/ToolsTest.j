
@import <OJUnit/OJTestCase.j>

@import "Tools.j"


@implementation ToolsTest : OJTestCase

-(void)testModel
{
    var model = [Tools testModel];
    [self assertNotNull:model];
    [self assert:"Testmodel"
          equals:[model name]];
}

-(void)testEntity
{
    var model = [Tools testModel];
    var entity = [model entityWithName:"Testentity"];
    [self assertNotNull:entity];
    [self assert:"Testentity"
          equals:[entity name]];
}

@end
