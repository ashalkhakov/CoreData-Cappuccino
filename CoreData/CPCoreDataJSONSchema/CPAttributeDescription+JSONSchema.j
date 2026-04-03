@import "../CPAttributeDescription.j"

@implementation CPAttributeDescription (CPJSONSchemaAttributeDescription)

+(id)attributeWithJSONSchemaObject:(id)schema
                     attributeName:(CPString)aName
                            entity:(CPEntityDescription)aEntity
{
    var type = schema.type;
    type = type !== undefined && type || "object";
    var CDClass = [CPJSONSchemaAttributeDescription _classWithJSONSchemaTypeName:type];
    return [[CDClass alloc] initWithJSONSchemaObject:schema
                                                name:aName
                                              entity:aEntity];
}

@end


@implementation CPJSONSchemaAttributeDescription : CPAttributeDescription
{
    CPArray _enumValues @accessors(getter=enumValues);
    CPString _valueFormat @accessors(property=valueFormat);
    CPString _propertyType @accessors(property=propertyType);

    id _rawJSON @accessors(property=rawJSON);
}

/*!
    Provide the Attribute class from the JSON schema type.
*/
+(int)_classWithJSONSchemaTypeName:(CPString)aType
{
    var result = JSONSchemaTypeToCoreDataType[aType][1];
    if (result != undefined)
        return result;
    return CPDUndefinedAttributeType;
};

/*!
    Provide the CoreData type from the JSON schema type.
*/
+(int)_typeWithJSONSchemaTypeName:(CPString)aType
{
    var result = JSONSchemaTypeToCoreDataType[aType][0];
    if (result != undefined)
        return result;
    return CPDUndefinedAttributeType;
};

-(id)initWithJSONSchemaObject:(id)aPropertyObject
                         name:(CPString)aName
                       entity:(CPEntityDescription)aEntity
{
    self = [super init];
    if (self)
    {
        [self setName:aName];
        [self setEntity:aEntity];
        [self setRawJSON:aPropertyObject];
        var type = aPropertyObject.type;
        if (type === undefined)
        {
            type = aPropertyObject["enum"];
            if (type !== undefined)
            {
                type = "enum";
                [self setEnumValues:aPropertyObject["enum"]];
            };
        }
        type = type !== undefined && type || "object";
        _propertyType = type;
        var format = aPropertyObject["format"];
        if (format !== undefined && format)
        {
            [self setTypeValue:CPDTransformableAttributeType];
        }
        else
        {
            [self setTypeValue:[[self class] _typeWithJSONSchemaTypeName:type]];
        }
        [self setClassValue:nil];
        [self setIsOptional:aPropertyObject.required ? NO : YES];
        [self setDefaultValue:aPropertyObject["default"] || nil];
        var format = aPropertyObject["format"] || [CPString stringWithFormat:"CoreDataJSONSchema_%s", type];
        [self setValueTransformerName:format];
        [self setValueFormat:format];
        if (type == "object")
        {
            // create a subschema
            var sub = [aEntity addSubentityWithSchema:aPropertyObject
                                         forAttribute:aName];
        }
        if (   type == "array"
            && aPropertyObject.items !== undefined
           )
        {
            var sub = [aEntity addSubentityWithSchema:aPropertyObject.items
                                         forAttribute:aName];
        }
    }
    return self;
}

-(void)setEnumValues:(id)values
{
    _enumValues = [CPArray arrayWithObjects:values
                                      count:values.length];
}

- (BOOL)acceptValue:(id)aValue
{
    var result = [super acceptValue:aValue];
    //TODO: use valueFormat to check the value
    return result
}

@end


var JSONSchemaTypeToCoreDataType = {}
JSONSchemaTypeToCoreDataType["string"] = [CPDStringAttributeType,
                                          CPJSONSchemaAttributeDescription
                                         ];
JSONSchemaTypeToCoreDataType["object"] = [CPDTransformableAttributeType,
                                          CPJSONSchemaAttributeDescription
                                         ];
JSONSchemaTypeToCoreDataType["enum"]   = [CPDBinaryDataAttributeType,
                                          CPJSONSchemaAttributeDescription
                                         ];
JSONSchemaTypeToCoreDataType["array"]  = [CPDTransformableAttributeType,
                                          CPJSONSchemaAttributeDescription
                                         ];

