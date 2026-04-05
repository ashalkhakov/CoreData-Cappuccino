
/*!
    Create a managed object model from a JSON Schema.
*/
@implementation CPEntityDescription (CPEntityDescriptionJSONSchema)

+(id)entityWithJSONSchema:(id)schema
                  forName:(CPString)aName
{
    return [[CPJSONSchemaEntityDescription alloc] initWithJSONSchema:schema
                                                             forName:aName];
}

@end


@implementation CPJSONSchemaEntityDescription : CPEntityDescription
{
    id _rawJSON @accessors(property=rawJSON);

    CPEntityDescription parentEntity @accessors;
    CPMutableDictionary subEntities;
}

-(id)init
{
    self = [super init];
    if (self)
    {
        subEntities = [CPMutableDictionary dictionary];
    }
    return self;
}

-(id)initWithJSONSchema:(id)schema
                forName:(CPString)aName
{
    self = [self init];
    if (self)
    {
        //TODO: validate the schema against the JSON schema spec
        // read the schema
        [self setName:aName];
        var properties = schema.properties;
        for (var name in properties)
        {
            var property = properties[name];
            [self addAttributeWithSchemaWithName:name
                                        property:property];
        };
    }
    return self;
}

- (CPManagedObject)createObject
{
	var newObject;
	var objectClassWithName = CPClassFromString(_name);
	var objectClassWithExternalName = CPClassFromString(_externalName);

	if(objectClassWithExternalName != nil)
	{
		newObject = [[objectClassWithExternalName alloc] initWithEntity:self]
	}
	else if(objectClassWithName != nil)
	{
		newObject = [[objectClassWithName alloc] initWithEntity:self];
	}
	else
	{
		newObject = [[CPManagedJSONObject alloc] initWithEntity:self];
	}
	return newObject;
}

-(void)addAttributeWithSchemaWithName:(CPString)name
                             property:(id)aPropertyObject
{
    var attr = [CPAttributeDescription attributeWithJSONSchemaObject:aPropertyObject
                                                       attributeName:name
                                                              entity:self];
    [self addProperty:attr];
}

-(CPEntityDescription)addSubentityWithSchema:(id)schema
                                forAttribute:(CPString)aName
{
    var entity = [CPEntityDescription entityWithJSONSchema:schema
                                                   forName:aName];
    [entity setParentEntity:self];
    [subEntities setObject:entity forKey:aName];
    return entity;
}

-(CPEntityDescription)subentityWithName:(CPString)name
{
    return [subEntities objectForKey:name];
}

/*!
    Create a managed object from a subentity.
*/
-(id)createAttributeWithSubentityPath:(CPString)aNamePath
{
    var firstDotIndex = aNamePath.indexOf(".");
    if (firstDotIndex === CPNotFound)
    {
        return [[self subentityWithName:aNamePath] createObject];
    }
    var firstKeyComponent = aNamePath.substring(0, firstDotIndex),
        remainingKeyPath = aNamePath.substring(firstDotIndex + 1),
        entity = [self valueForKey:firstKeyComponent];
    return [entity valueForKeyPath:remainingKeyPath];
}

/*!
    Provide a dictionary initialized with the default values.
*/
-(CPDictionary)initialDataForObject:(CPManagedObject)aObject
{
    var result = [[CPMutableDictionary alloc] init];
    var e = [[self properties] objectEnumerator];
    var property;
    while ((property = [e nextObject]) != nil)
    {
        var propName = [property name];
        var value = [property defaultValue];
        if (value != nil)
        {
            value = [CPManagedJSONObject _objjObjectWithJSONObject:value
                                                         forObject:aObject
                                                        forKeyPath:propName];
        }
        else if (![property isOptional])
        {
            if ([property propertyType] == "array")
            {
                value = [];
            }
            else
            {
                value = [self createAttributeWithSubentityPath:propName];
            }
        }
        else if ([property propertyType] == "array")
        {
            // arrays are always initialized as an emtpy array
            value = [];
        }
        [result setObject:value forKey:propName];
    }
    return result;
}

@end

