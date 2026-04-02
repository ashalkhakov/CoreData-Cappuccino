//
//  CPEntityDescription.j
//
//  Created by Raphael Bartolome on 15.10.09.
//

@import <Foundation/Foundation.j>
@import "CPPropertyDescription.j"
@import "CPAttributeDescription.j"
@import "CPRelationshipDescription.j"
@import "CPManagedObject.j"

@class CPManagedObject;
@class CPManagedObjectModel;

@implementation CPEntityDescription : CPObject
{
	CPManagedObjectModel _model @accessors(property=model);
	CPString _name @accessors(property=name);
	CPString _externalName @accessors(property=externalName);
	CPMutableSet _properties @accessors(property=properties);

	CPDictionary _attributesByName @accessors(getter=attributesByName);
	CPDictionary _relationshipsByName @accessors(getter=relationshipsByName);
    CPDictionary _propertiesByName @accessors(getter=propertiesByName);
	CPArray _propertyNames @accessors(getter=propertyNames);
}

- (id)init
{
	if(self = [super init])
	{
		_properties = [[CPMutableSet alloc] init];
        _attributesByName = [[CPMutableDictionary alloc] init];
        _relationshipsByName = [[CPMutableDictionary alloc] init];
        _propertiesByName = [[CPMutableDictionary alloc] init];
	}
	return self;
}

+ (CPManagedObject)insertNewObjectForEntityForName:(CPString)aEntityName inManagedObjectContext:(CPManagedObjectContext) aContext
{
	return [aContext insertNewObjectForEntityForName:aEntityName];
}

- (CPManagedObject)createObject
{
	var newObject;
	var objectClassWithName = CPClassFromString(_name);
	var objectClassWithExternaName = CPClassFromString(_externalName);

	if(objectClassWithExternaName != nil)
	{
		newObject = [[objectClassWithExternaName alloc] initWithEntity:self]
	}
	else if(objectClassWithName != nil)
	{
		newObject = [[objectClassWithName alloc] initWithEntity:self];
	}
	else
	{
		newObject = [[CPManagedObject alloc] initWithEntity:self];
	}
	return newObject;
}

- (void)addRelationshipWithName:(CPString)name toMany:(BOOL)toMany optional:(BOOL)isOptional deleteRule:(int) aDeleteRule destination:(CPString)destinationEntityName
{
	var tmp = [[CPRelationshipDescription alloc] init];
	[tmp setName:name];
	[tmp setEntity:self];
	[tmp setIsToMany:toMany];
	[tmp setIsOptional:isOptional];
	[tmp setDeleteRule:aDeleteRule];
	[tmp setDestinationEntityName:destinationEntityName];
	[self addProperty:tmp];
}

- (void)addAttributeWithName:(CPString)name classValue:(CPString)aClassValue typeValue:(int)aAttributeType optional:(BOOL)isOptional
{
	var tmp = [[CPAttributeDescription alloc] init];
	[tmp setName:name];
	[tmp setEntity:self];
	[tmp setTypeValue:aAttributeType];
	[tmp setClassValue:aClassValue];
	[tmp setIsOptional:isOptional];
	[self addProperty:[tmp copy]];
}

- (void)addProperty:(CPPropertyDescription)property
{
	[_properties addObject:property];
	_attributesByName = [self _filteredPropertiesOfClass: [CPAttributeDescription class]];
	_relationshipsByName = [self _filteredPropertiesOfClass: [CPRelationshipDescription class]];
    _propertiesByName = [self _filteredPropertiesOfClass: Nil];
	_propertyNames = [_propertiesByName allKeys];
}

-(CPAttributeDescription)propertyWithName:(CPString)aName
{
    return [_propertiesByName valueForKey:aName];
}

-(BOOL)isAttribute:(CPAttributeDescription)attribute
{
    return [attribute isKindOfClass:[CPAttributeDescription class]];
}

-(BOOL)isAttributeName:(CPString)aName
{
    return [[_propertiesByName valueForKey:aName] isKindOfClass:[CPAttributeDescription class]];
}

-(BOOL)isMandatoryAttribute:(CPAttributeDescription)attribute
{
    var attr = [_attributesByName valueForKey:[attribute name]];
    return ![attr isOptional];
}

-(BOOL)isMandatoryAttributeName:(CPString)attrName
{
    var attr = [_attributesByName valueForKey:attrName];
    return ![attr isOptional];
}

-(BOOL)isRelationship:(CPAttributeDescription)attribute
{
    return [attribute isKindOfClass:[CPRelationshipDescription class]];
}

-(BOOL)isRelationshipName:(CPString)attrName
{
    return !![_relationshipsByName valueForKey:attrName];
}

-(BOOL)isMandatoryRelationship:(CPAttributeDescription)attribute
{
    var attr = [_relationshipsByName valueForKey:[attribute name]];
    return ![attr isOptional];
}

-(BOOL)isMandatoryRelationshipName:(CPString)propName
{
    var prop = [_relationshipsByName valueForKey:propName];
    return ![prop isOptional];
}

- (CPDictionary) _filteredPropertiesOfClass: (Class) aClass
{
	var dict;
	var e;
	var property;

	dict = [[CPMutableDictionary alloc] init];
	e = [_properties objectEnumerator];
	while ((property = [e nextObject]) != nil)
    {
      if (aClass == Nil || [property isKindOfClass: aClass])
        {
			[dict setObject: property forKey: [property name]];
        }
    }

	return dict;
}


- (BOOL)acceptValue:(id) aValue forProperty:(CPString) aKey
{
	var theProperty = [_propertiesByName objectForKey:aKey]
	return [theProperty acceptValue:aValue];
}

/**
    Transform a value with the properties transformer into an internal value.

    This is used by the managed object when a value is returned from the object.
*/
- (id)transformValue:(id)aValue forProperty:(CPString)aKey
{
	var theProperty = [[self attributesByName] objectForKey:aKey];
    if (theProperty)
    {
        var transformer = [self _transformerForProperty:theProperty];
        if (transformer)
        {
            return [transformer transformedValue:aValue];
        }
    }
    return aValue;
}


- (id)reverseTransformValue:(id)aValue forProperty:(CPString)aKey
{
	var theProperty = [[self attributesByName] objectForKey:aKey];
    if (theProperty)
    {
        var transformer = [self _transformerForProperty:theProperty];
        if (transformer && [[transformer class] allowsReverseTransformation])
        {
            return [transformer reverseTransformedValue:aValue];
        }
    }
    return aValue;
}

-(CPString)_transformerForProperty:(CPPropertyDescription)aProperty
{
    var transformerName = "";
    var type = [aProperty typeValue];
    if (type == CPDTransformableAttributeType)
    {
        transformerName = [aProperty valueTransformerName];
    }
    else
    {// This allows us to write transformers for standard data types eg. CPDate
        transformerName = [aProperty typeName];
        transformerName += "ValueTransformer";
    }
    var transformer = [CPValueTransformer valueTransformerForName:transformerName];
    //if (   type == CPDTransformableAttributeType
    //    && !transformer
    //   )
    //   CPLog.warn("Transformer %s not found!", transformerName);
    return transformer
}

- (BOOL) isEqual:(CPEntityDescription)aEntity
{
	return [[aEntity name] isEqualToString:_name];
}


- (CPString)stringRepresentation
{
	var result = "\n";
	result = result + "\n";
	result = result + "-CPEntityDescription-";
	result = result + "\n***********";
	result = result + "\n";
	result = result + "name:" + [self name] + ";";
	result = result + "\n";
	result = result + "externalName:" + [self externalName] + ";";
	var propertiesE = [_properties objectEnumerator];
	var aProperty;
	while((aProperty = [propertiesE nextObject]))
	{
		result = result + "\n";
		result = result + [aProperty stringRepresentation];
	}
	return result;
}

@end
