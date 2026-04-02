@import "CPManagedObject.j"

@implementation CPManagedObject (CPManagedJSONObject)

/*!
    Provide a managed object with raw JSON data.

    The entity must provide a managed object which responds to setJSONObject.
*/
+(id)objectWithJSONObject:(id)JSONObject
                   entity:(CPEntityDescription)aEntity
{
    var result = [aEntity createObject];
    if (result)
    {
        [result setJSONObject:JSONObject];
    }
    return result
}

@end


/*!
    A managed object which works with raw JSON data.
*/
@implementation CPManagedJSONObject : CPManagedObject
{
    CPManagedObject _parent @accessors(property=parentObject);
    CPManagedObject _keyPath @accessors(property=keyPath);

    BOOL _updateLock @accessors(getter=updateLock);
}

/*!
  Create a clone from an existing managed object.

  The clone will have the exact same data and the same global ID.
  */
-(id)clone
{
    var result = [[self entity] createObject];
    if (result)
    {
        [result setJSONObject:[self JSONObject]];
        [[result objectID] updateWithObjectID:_objectID];
    }
    return result;
}

- (void)_updateWithObject:(CPManagedObject) aObject
{
    [_objectID updateWithObjectID:[aObject objectID]];
    [self setJSONObject:[aObject JSONObject]];
}

-(void)objectDidChange
{
    [_context _objectDidChange:self];
    if ([_context autoSaveChanges])
    {
        [_context saveChanges:nil];
    }
}

/*!
    Create a new subobject for an object by providing the key path.

    A new object will be returned which was created from the subentity assigned
    to the key path.
    The new object has an association to the receiver but is not assigned to
    a property of the receiver. Any changes made to the new object will mark
    the receiver as changed even if the object is or will never be assigned to
    a property of the receiver. The new object must not be used in an other
    object than the receiver.
*/
- (CPManagedObject)createObjectWithKeyPath:(CPString)keyPath
{
    var entity = [self entity],
        key = keyPath,
        firstKeyComponent;
    while (keyPath)
    {
        var firstDotIndex = keyPath.indexOf(".");
        if (firstDotIndex === CPNotFound)
        {
            firstKeyComponent = keyPath;
            keyPath = nil;
        }
        else
        {
            firstKeyComponent = keyPath.substring(0, firstDotIndex);
            keyPath = keyPath.substring(firstDotIndex + 1);
        }
        entity = [entity subentityWithName:firstKeyComponent];
        if (!keyPath)
        {
            var result = [entity createObject];
            [result setParentObject:self];
            [result setKeyPath:key];
            return result;
        }
    }
    return nil;
}

/*!
    Reset all values to the defaults by converting the default from JSON.
*/
- (void)_resetObjectDataForProperties
{
	_data = [_entity initialDataForObject:self];
}

/**
    Replace the object data with data from a JSObject.
*/
-(void)setJSONObject:(id)JSONObject
{
    _updateLock = YES;
    [self _setData:[CPManagedJSONObject _objjObjectWithJSONObject:JSONObject
                                                        forObject:self]];
    _updateLock = NO;
}

/**
    Provide the object data as JSObject.
*/
-(id)JSONObject
{
    return [CPManagedJSONObject _JSONObjectWithObjjObject:[self data]
                                               withEntity:[self entity]];
}

-(void)setRawData:(CPDictionary)aDictionary
{
    [self _setData:aDictionary];
}

/**
    Update the object with data from a JSObject.

    Doesn't remove existing attributes, just replaces existing data with data
    from the JSON object.
*/
-(void)updateWithJSONObject:(id)jsonObject
{
    var asDictionary = [CPDictionary dictionaryWithJSObject:jsonObject];
    var existing = [self data];
    var keys = [[asDictionary allKeys] objectEnumerator];
    var key;
    while ((key = [keys nextObject]) != nil)
    {
        [existing setObject:[asDictionary valueForKey:key]
                     forKey:key];
    }
}

/*!
    Provide a objective-j object from a JSON-Object.
*/
+(CPObject)_objjObjectWithJSONObject:(id)JSONObject
                           forObject:(CPManagedJSONObject)aObject
{
    return [self _objjObjectWithJSONObject:JSONObject
                                 forObject:aObject
                                forKeyPath:""];
}

+(CPObject)_objjObjectWithJSONObject:(id)JSONObject
                           forObject:aObject
                          forKeyPath:(CPString)keyPath
{
    var propName;
    var lastDotIndex = keyPath.lastIndexOf(".");
    if (lastDotIndex === CPNotFound)
    {
        propName = keyPath;
    }
    else
    {
        propName = keyPath.substring(lastDotIndex + 1);
    }
    if (JSONObject == nil)
    {
        if (propName)
        {
            var aEntity = [aObject entity];
            var property = [aEntity propertyWithName:propName];
            if ([property propertyType] == "array")
            {
                return [CPArray array];
            }
        }
        return JSONObject;
    }
    if (JSONObject instanceof Array)
    {
        for (var i=0; i < JSONObject.length; i++)
        {
            var old = [JSONObject objectAtIndex:i];
            var value = [CPManagedJSONObject _objjObjectWithJSONObject:old
                                                             forObject:aObject
                                                            forKeyPath:keyPath];
            if (value !== old)
            {
                [JSONObject replaceObjectAtIndex:i
                                      withObject:value];
            }

        }
        return JSONObject;
    }
    if ((typeof JSONObject) == typeof {})
    {
        var result = nil;
        // provide as a managed object
        var aEntity = [aObject entity];
        if (propName)
        {
            // we must use the subentity for the property
            //TODO: what shall we do if we have no subentity
            var top = aObject;
            while ([top parentObject] != nil)
            {
                top = [top parentObject];
            }
            aEntity = [aEntity subentityWithName:propName];
            aObject = [aEntity createObject],
            [aObject setKeyPath:keyPath];
            [aObject setParentObject:top];
            result = aObject;
        }
        else
        {
            // the root object must be a dictionary
            result = [CPMutableDictionary dictionary];
        }
        var e = [[aEntity properties] objectEnumerator];
        var property;
        while ((property = [e nextObject]) != nil)
        {
            var key = [property name];
            var value = JSONObject[key];
            if (value === undefined)
            {
                value = [property defaultValue];
            }
            var path;
            if (keyPath)
            {
                path = [keyPath stringByAppendingFormat:".%s", key];
            }
            else
            {
                path = key;
            }
            value = [CPManagedJSONObject _objjObjectWithJSONObject:value
                                                         forObject:aObject
                                                        forKeyPath:path];
            [result setValue:value
                      forKey:key];
        }
        return result;
    }
    // no conversion needed
    return JSONObject;
}

+(id)_JSONObjectWithObjjObject:(id)objjObject
                    withEntity:(CPEntityDescription)aEntity
{
    return [CPManagedJSONObject _JSONObjectWithObjjObject:objjObject
                                               withEntity:aEntity
                                              forProperty:nil];
}

+(id)_JSONObjectWithObjjObject:(id)objjObject
                    withEntity:aEntity
                   forProperty:(CPString)propName
{
    if ([objjObject isKindOfClass:[CPArray class]])
    {
        var result = [];
        if (objjObject.length == 0)
        {
            var property = [aEntity propertyWithName:propName];
            if ([property isOptional])
            {
                result = nil;
            }
        }
        else
        {
            aEntity = [aEntity subentityWithName:propName];
            for (var i=0; i < objjObject.length; i++)
            {
                var value = [CPManagedJSONObject _JSONObjectWithObjjObject:[objjObject objectAtIndex:i]
                                                                withEntity:aEntity
                                                               forProperty:propName];
                [result addObject:value];
            }
        }
        return result;
    }
    if ([objjObject isKindOfClass:[CPDictionary class]])
    {
        if (propName)
        {
            // we must use the subentity for the property
            //TODO: what shall we do if we have no subentity
            aEntity = [aEntity subentityWithName:propName];
        }
        var result = {},
            e = [[aEntity properties] objectEnumerator],
            property;
        while ((property = [e nextObject]) != nil)
        {
            var key = [property name];
            var value = [objjObject valueForKey:key];
            if (value === undefined || value == nil)
            {
                if ([property isOptional])
                {
                    value = nil;
                }
                else
                {
                    value = [property defaultValue];
                }
            }
            if (![property isOptional] || value != nil)
            {
                value = [CPManagedJSONObject _JSONObjectWithObjjObject:value
                                                            withEntity:aEntity
                                                           forProperty:key];
                if (![property isOptional] || value != nil)
                {
                    result[key] = value;
                }
            }
        }
        return result
    }
    if ([objjObject isKindOfClass:[CPManagedJSONObject class]])
    {
        return [objjObject JSONObject];
    }
    return objjObject;
}

-(CPString)description
{
    return [CPString stringWithFormat:"%@ for entity %s",[self class], [[self entity] name]];
}

@end


@implementation CPManagedJSONObject (CPCoreDataSerialization)

- (CPDictionary)serializeProperties:(CPDictionary)data
{
    var JSObj = [CPManagedJSONObject _JSONObjectWithObjjObject:data
                                                    withEntity:[self entity]];
    return [CPString JSONFromObject:JSObj];
}

- (CPDictionary)deserializeProperties:(CPDictionary)data
{
    var obj = [CPManagedJSONObject _objjObjectWithJSONObject:[data objectFromJSON]
                                                   forObject:self];
    return obj;
}

@end


/*!
  We need a special KeyValueObserving for subobjects in managed objects because
  the managed object needs to be informed about changes to update the state in
  it's managed object.
  */
@implementation CPManagedJSONObject (KeyValueObserving)

- (void)willChangeValueForKey:(CPString)aKey
{
    if (_updateLock)
    {
        return;
    }
    if (_context == nil && _parent != nil)
    {
        var firstDot = _keyPath.indexOf(".");
        if (firstDot !== CPNotFound)
        {
            aKey = _keyPath.substring(0, firstDot);
        }
        else
        {
            aKey = _keyPath;
        }
        if ([_parent updateLock])
        {
            return;
        }
        [_parent willChangeValueForKey:aKey];
    }
    [super willChangeValueForKey:aKey];
}

- (void)didChangeValueForKey:(CPString)aKey
{
    if (_updateLock)
    {
        return;
    }
    if (_context == nil && _parent != nil)
    {
        var firstDot = _keyPath.indexOf(".");
        if (firstDot !== CPNotFound)
        {
            aKey = _keyPath.substring(0, firstDot);
        }
        else
        {
            aKey = _keyPath;
        }
        if ([_parent updateLock])
        {
            return;
        }
        [_parent didChangeValueForKey:aKey];
    }
    [super didChangeValueForKey:aKey];
}


@end

