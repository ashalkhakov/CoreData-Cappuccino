
@import <OJUnit/OJTestCase.j>


@implementation CPErrorTest : OJTestCase

-(void)testConstructor
{
    var error = [CPError errorWithDomain:"Domain"
                                    code:42
                                userInfo:[CPDictionary dictionary]];
    [self assertNotNull:error
                message:"Constructor returned no instance!"];
    [self assert:"Domain" equals:[error domain]];
    [self assert:42 equals:[error code]];
    [self assert:[CPDictionary class] equals:[[error userInfo] class]];
}

-(void)testDescription
{
    var userInfo = [CPDictionary dictionary];
    var error = [CPError errorWithDomain:"Domain"
                                    code:42
                                userInfo:userInfo];
    [self assert:"Error Domain=Domain Code=42 UserInfo={\n} CPError (Domain error 42)"
          equals:[error description]];
}

-(void)testLocalizedDescription
{
    var userInfo = [CPDictionary dictionary];
    var error = [CPError errorWithDomain:"Domain"
                                    code:42
                                userInfo:userInfo];
    [self assert:"CPError (Domain error 42)"
          equals:[error localizedDescription]];
    [userInfo setValue:"The localized Description"
                forKey:CPLocalizedDescriptionKey];
    [self assert:"The localized Description"
          equals:[error localizedDescription]];
}

-(void)testLocalizedFailureReason {
    var userInfo = [CPDictionary dictionary];
    [userInfo setValue:"failure reason"
                forKey:CPLocalizedFailureReasonErrorKey];
    var error = [CPError errorWithDomain:"Domain"
                                    code:42
                                userInfo:userInfo];
    [self assert:"failure reason"
          equals:[error localizedFailureReason]];
}

-(void)testLocalizedRecoveryOptions {
    var userInfo = [CPDictionary dictionary];
    [userInfo setValue:"recovery options"
                forKey:CPLocalizedRecoveryOptionsErrorKey];
    var error = [CPError errorWithDomain:"Domain"
                                    code:42
                                userInfo:userInfo];
    [self assert:"recovery options"
          equals:[error localizedRecoveryOptions]];
}

-(void)testLocalizedRecoverySuggestion {
    var userInfo = [CPDictionary dictionary];
    [userInfo setValue:"recovery suggestion"
                forKey:CPLocalizedRecoverySuggestionErrorKey];
    var error = [CPError errorWithDomain:"Domain"
                                    code:42
                                userInfo:userInfo];
    [self assert:"recovery suggestion"
          equals:[error localizedRecoverySuggestion]];
}

-(void)testRecoveryAttempter {
    var userInfo = [CPDictionary dictionary];
    [userInfo setValue:"recovery attempter"
                forKey:CPRecoveryAttempterErrorKey];
    var error = [CPError errorWithDomain:"Domain"
                                    code:42
                                userInfo:userInfo];
    [self assert:"recovery attempter"
          equals:[error recoveryAttempter]];
}

@end

