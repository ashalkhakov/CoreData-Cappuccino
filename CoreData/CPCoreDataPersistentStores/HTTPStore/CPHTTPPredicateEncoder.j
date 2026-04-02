//
//  CPHTTPPredicateEncoder.j
//
//  Encode a CPPredicate (or a raw CPDictionary predicate AST) into the
//  OrdersAPI cdFetch predicate AST format.
//
//  Supported operators
//  -------------------
//  Comparison:   ==  !=  <  <=  >  >=  contains  beginswith  in
//  Null-checks:  == nil  (isnull),  != nil  (notnull)
//  Compound:     and  or  not
//
//  Raw-dictionary pass-through
//  ---------------------------
//  If the predicate passed to +encodePredicateToAST: is already a
//  CPDictionary it is returned unchanged.  This lets callers supply a
//  hand-crafted AST when the high-level CPPredicate classes are not
//  available:
//
//      var pred = @{ @"op": @"beginswith", @"key": @"fullName", @"value": @"A" };
//      [request setPredicate:pred];
//

@import <Foundation/Foundation.j>


@implementation CPHTTPPredicateEncoder : CPObject
{
}

/*!
    Encode predicate to an OrdersAPI predicate AST dictionary.

    @param predicate  A CPCompoundPredicate, CPComparisonPredicate, or a
                      raw CPDictionary AST.  Pass nil to receive nil back.
    @return           A CPDictionary suitable for JSON serialisation into
                      cdFetch's "predicate" field, or nil.
*/
+ (CPDictionary)encodePredicateToAST:(id)predicate
{
    if (predicate === nil || predicate === null)
        return nil;

    // Raw dictionary pass-through
    if ([predicate isKindOfClass:[CPDictionary class]])
        return predicate;

    if ([predicate isKindOfClass:[CPCompoundPredicate class]])
        return [self _encodeCompoundPredicate:predicate];

    if ([predicate isKindOfClass:[CPComparisonPredicate class]])
        return [self _encodeComparisonPredicate:predicate];

    CPLog.warn(@"CPHTTPPredicateEncoder: cannot encode predicate of class " + [predicate className]);
    return nil;
}


// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

+ (CPDictionary)_encodeCompoundPredicate:(CPCompoundPredicate)predicate
{
    var logicalType   = [predicate compoundPredicateType],
        subpredicates = [predicate subpredicates],
        encodedSubs   = [[CPMutableArray alloc] init];

    var e = [subpredicates objectEnumerator],
        sub;
    while ((sub = [e nextObject]))
    {
        var encoded = [self encodePredicateToAST:sub];
        if (encoded !== nil)
            [encodedSubs addObject:encoded];
    }

    var op;
    if (logicalType == CPAndPredicateType)
        op = @"and";
    else if (logicalType == CPOrPredicateType)
        op = @"or";
    else
        op = @"not";

    if (op === @"not" && [encodedSubs count] == 1)
        return [CPDictionary dictionaryWithObjectsAndKeys:
                    op,                            @"op",
                    [encodedSubs objectAtIndex:0], @"sub", nil];

    return [CPDictionary dictionaryWithObjectsAndKeys:
                op,         @"op",
                encodedSubs, @"subs", nil];
}

+ (CPDictionary)_encodeComparisonPredicate:(CPComparisonPredicate)predicate
{
    var lhs          = [predicate leftExpression],
        rhs          = [predicate rightExpression],
        operatorType = [predicate predicateOperatorType];

    var key   = nil,
        value = nil;

    if ([lhs expressionType] == CPKeyPathExpressionType)
        key = [lhs keyPath];
    if ([rhs expressionType] == CPConstantValueExpressionType)
        value = [rhs constantValue];

    // isnull / notnull
    if (   operatorType == CPEqualToPredicateOperatorType
        && (value === nil || value === null || value === [CPNull null]))
    {
        return [CPDictionary dictionaryWithObjectsAndKeys:
                    @"isnull", @"op",
                    key,       @"key", nil];
    }
    if (   operatorType == CPNotEqualToPredicateOperatorType
        && (value === nil || value === null || value === [CPNull null]))
    {
        return [CPDictionary dictionaryWithObjectsAndKeys:
                    @"notnull", @"op",
                    key,        @"key", nil];
    }

    // in: the rhs is a collection
    if (operatorType == CPInPredicateOperatorType)
    {
        var items = (value !== nil && [value isKindOfClass:[CPSet class]])
                        ? [value allObjects]
                        : value;
        return [CPDictionary dictionaryWithObjectsAndKeys:
                    @"in", @"op",
                    key,   @"key",
                    items, @"value", nil];
    }

    var opString = [self _operatorStringForType:operatorType];
    if (opString === nil)
    {
        CPLog.warn(@"CPHTTPPredicateEncoder: unsupported operator type " + operatorType);
        return nil;
    }

    return [CPDictionary dictionaryWithObjectsAndKeys:
                opString, @"op",
                key,      @"key",
                value,    @"value", nil];
}

+ (CPString)_operatorStringForType:(int)operatorType
{
    switch (operatorType)
    {
        case CPEqualToPredicateOperatorType:              return @"==";
        case CPNotEqualToPredicateOperatorType:           return @"!=";
        case CPLessThanPredicateOperatorType:             return @"<";
        case CPLessThanOrEqualToPredicateOperatorType:    return @"<=";
        case CPGreaterThanPredicateOperatorType:          return @">";
        case CPGreaterThanOrEqualToPredicateOperatorType: return @">=";
        case CPContainsPredicateOperatorType:             return @"contains";
        case CPBeginsWithPredicateOperatorType:           return @"beginswith";
        default:                                          return nil;
    }
}

@end
