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
//  CPDictionary it is normalized and returned.  Operator aliases such as
//  "=" are mapped to their canonical form (e.g. "==") so the server never
//  sees an unsupported operator.  This lets callers supply a hand-crafted
//  AST when the high-level CPPredicate classes are not available:
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

    // Raw dictionary pass-through (with operator normalization)
    if ([predicate isKindOfClass:[CPDictionary class]])
        return [self _normalizeDictionaryAST:predicate];

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
                    [encodedSubs objectAtIndex:0], @"sub"];

    return [CPDictionary dictionaryWithObjectsAndKeys:
                op,         @"op",
                encodedSubs, @"subs"];
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
                    key,       @"key"];
    }
    if (   operatorType == CPNotEqualToPredicateOperatorType
        && (value === nil || value === null || value === [CPNull null]))
    {
        return [CPDictionary dictionaryWithObjectsAndKeys:
                    @"notnull", @"op",
                    key,        @"key"];
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
                    items, @"value"];
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
                value,    @"value"];
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

+ (CPString)_normalizedOpString:(CPString)op
{
    // Normalize common aliases to the canonical form expected by the server
    if (op === @"=")   return @"==";
    if (op === @"lt")  return @"<";
    if (op === @"lte") return @"<=";
    if (op === @"gt")  return @">";
    if (op === @"gte") return @">=";
    if (op === @"ne")  return @"!=";
    return op;
}

/*!
    Recursively walk a raw CPDictionary predicate AST and normalize operator
    strings so aliases like "=" are converted to the canonical form "==" that
    the server accepts.
*/
+ (CPDictionary)_normalizeDictionaryAST:(CPDictionary)ast
{
    var op = [ast objectForKey:@"op"];
    if (op === nil)
        return ast;

    var normalizedOp = [self _normalizedOpString:op];

    // Compound node: recurse into sub-predicates
    if (op === @"and" || op === @"or")
    {
        var subs    = [ast objectForKey:@"subs"],
            newSubs = [[CPMutableArray alloc] init];
        if (subs !== nil)
        {
            var e = [subs objectEnumerator], sub;
            while ((sub = [e nextObject]))
                [newSubs addObject:([sub isKindOfClass:[CPDictionary class]]
                                        ? [self _normalizeDictionaryAST:sub]
                                        : sub)];
        }
        var result = [[CPMutableDictionary alloc] initWithDictionary:ast];
        [result setObject:normalizedOp forKey:@"op"];
        [result setObject:newSubs      forKey:@"subs"];
        return result;
    }

    if (op === @"not")
    {
        var sub    = [ast objectForKey:@"sub"],
            newSub = ([sub isKindOfClass:[CPDictionary class]]
                          ? [self _normalizeDictionaryAST:sub]
                          : sub);
        var result = [[CPMutableDictionary alloc] initWithDictionary:ast];
        [result setObject:normalizedOp forKey:@"op"];
        if (newSub !== nil)
            [result setObject:newSub forKey:@"sub"];
        return result;
    }

    // Leaf comparison node — just fix the op string if needed
    if (normalizedOp === op)
        return ast;

    var result = [[CPMutableDictionary alloc] initWithDictionary:ast];
    [result setObject:normalizedOp forKey:@"op"];
    return result;
}

@end
