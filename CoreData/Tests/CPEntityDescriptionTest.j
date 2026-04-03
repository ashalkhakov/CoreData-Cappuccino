
@import <OJUnit/OJTestCase.j>

@import "Tools.j"


@implementation CPEntityDescriptionTest : OJTestCase
{
    CPEntityDescription entity;
}

-(void)setUp
{
    entity = [[CPEntityDescription alloc] init];
    var attr = [[CPAttributeDescription alloc] init];
    [attr setName:"transform"];
    [attr setTypeValue:CPDTransformableAttributeType];
    [attr setValueTransformerName:"TestValueTransformer"];
    [entity addProperty:attr];
}

-(void)testTransformationWithoutRegisteredTransformer
{
    [self assert:"value"
            equals:[entity transformValue:"value"
                              forProperty:"transform"]];
}

-(void)testReverseTransformationWithoutRegisteredTransformer
{
    [self assert:"value"
            equals:[entity reverseTransformValue:"value"
                                     forProperty:"transform"]];
}

-(void)testTransformationWithRegisteredTransformer
{
    [CPValueTransformer setValueTransformer:[[TestValueTransformer alloc] init]
                                    forName:@"TestValueTransformer"];
    [self assert:"Transformed:value"
            equals:[entity transformValue:"value"
                              forProperty:"transform"]];
}

-(void)testTransformationWithRegisteredTransformerReverse
{
    [CPValueTransformer setValueTransformer:[[TestValueTransformer alloc] init]
                                    forName:@"TestValueTransformer"];
    [self assert:"Reverse:value"
            equals:[entity reverseTransformValue:"value"
                                     forProperty:"transform"]];
}

@end


@implementation TestValueTransformer : CPValueTransformer

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

