@import <OJUnit/OJTestCase.j>

@import "CoreData.j"


/*!
    Unit tests for the new Xcode 4+ XML CoreData model format support.

    Tests are divided into two groups:
      1. Type-mapping helpers — always run, no I/O needed.
      2. Full XML parser  — runs only when DOMParser is available (browser or
         environment with DOM support); gracefully skipped in Narwhal/ojtest.
*/
@implementation CPXCDataModelXMLParserTest : OJTestCase
{
}


// ---------------------------------------------------------------------------
// Attribute type mapping
// ---------------------------------------------------------------------------

- (void)testAttributeTypeString
{
    [self assert:CPDStringAttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"String"]];
}

- (void)testAttributeTypeInteger16
{
    [self assert:CPDInteger16AttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Integer 16"]];
}

- (void)testAttributeTypeInteger32
{
    [self assert:CPDInteger32AttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Integer 32"]];
}

- (void)testAttributeTypeInteger64
{
    [self assert:CPDInteger64AttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Integer 64"]];
}

- (void)testAttributeTypeFloat
{
    [self assert:CPDFloatAttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Float"]];
}

- (void)testAttributeTypeDouble
{
    [self assert:CPDDoubleAttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Double"]];
}

- (void)testAttributeTypeDecimal
{
    [self assert:CPDDecimalAttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Decimal"]];
}

- (void)testAttributeTypeBoolean
{
    [self assert:CPDBooleanAttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Boolean"]];
}

- (void)testAttributeTypeDate
{
    [self assert:CPDDateAttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Date"]];
}

- (void)testAttributeTypeBinaryData
{
    [self assert:CPDBinaryDataAttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Binary Data"]];
}

- (void)testAttributeTypeTransformable
{
    [self assert:CPDTransformableAttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"Transformable"]];
}

- (void)testAttributeTypeUnknownFallsBack
{
    [self assert:CPDUndefinedAttributeType
          equals:[CPManagedObjectModel _attributeTypeForXCDataModelType:@"UnknownType"]];
}


// ---------------------------------------------------------------------------
// Class-value mapping
// ---------------------------------------------------------------------------

- (void)testClassValueString
{
    [self assert:@"CPString"
          equals:[CPManagedObjectModel _classValueForXCDataModelType:@"String"]];
}

- (void)testClassValueInteger32
{
    [self assert:@"CPNumber"
          equals:[CPManagedObjectModel _classValueForXCDataModelType:@"Integer 32"]];
}

- (void)testClassValueDouble
{
    [self assert:@"CPNumber"
          equals:[CPManagedObjectModel _classValueForXCDataModelType:@"Double"]];
}

- (void)testClassValueBoolean
{
    [self assert:@"CPNumber"
          equals:[CPManagedObjectModel _classValueForXCDataModelType:@"Boolean"]];
}

- (void)testClassValueDate
{
    [self assert:@"CPDate"
          equals:[CPManagedObjectModel _classValueForXCDataModelType:@"Date"]];
}

- (void)testClassValueBinaryData
{
    [self assert:@"CPData"
          equals:[CPManagedObjectModel _classValueForXCDataModelType:@"Binary Data"]];
}

- (void)testClassValueTransformable
{
    [self assert:@"CPObject"
          equals:[CPManagedObjectModel _classValueForXCDataModelType:@"Transformable"]];
}

- (void)testClassValueUUID
{
    [self assert:@"CPString"
          equals:[CPManagedObjectModel _classValueForXCDataModelType:@"UUID"]];
}

- (void)testClassValueUnknownFallsBackToString
{
    [self assert:@"CPString"
          equals:[CPManagedObjectModel _classValueForXCDataModelType:@"SomeNewType"]];
}


// ---------------------------------------------------------------------------
// Delete-rule mapping
// ---------------------------------------------------------------------------

- (void)testDeleteRuleNullify
{
    [self assert:CPRelationshipDescriptionDeleteRuleNullify
          equals:[CPManagedObjectModel _deleteRuleForXCDataModelString:@"Nullify"]];
}

- (void)testDeleteRuleCascade
{
    [self assert:CPRelationshipDescriptionDeleteRuleCascade
          equals:[CPManagedObjectModel _deleteRuleForXCDataModelString:@"Cascade"]];
}

- (void)testDeleteRuleDeny
{
    [self assert:CPRelationshipDescriptionDeleteRuleDeny
          equals:[CPManagedObjectModel _deleteRuleForXCDataModelString:@"Deny"]];
}

- (void)testDeleteRuleNoAction
{
    [self assert:CPRelationshipDescriptionDeleteRuleNoAction
          equals:[CPManagedObjectModel _deleteRuleForXCDataModelString:@"No Action"]];
}

- (void)testDeleteRuleUnknownDefaultsToNullify
{
    [self assert:CPRelationshipDescriptionDeleteRuleNullify
          equals:[CPManagedObjectModel _deleteRuleForXCDataModelString:@"Unknown"]];
}


// ---------------------------------------------------------------------------
// Full XML parsing  (browser/DOM environment only)
// ---------------------------------------------------------------------------

- (void)testParseContentsXMLEntities
{
    if (typeof DOMParser === "undefined")
        return; // Skip in non-browser test runners

    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            + '<model type="com.apple.IDECoreDataModeler.DataModel">'
            + '  <entity name="Person" representedClassName="Person" syncable="YES">'
            + '    <attribute name="firstName" optional="YES" attributeType="String"/>'
            + '    <attribute name="age"       optional="NO"  attributeType="Integer 32" defaultValueString="0"/>'
            + '    <relationship name="addresses" optional="YES" toMany="YES" deletionRule="Cascade"'
            + '                  destinationEntity="Address" inverseName="person" inverseEntity="Address"/>'
            + '  </entity>'
            + '  <entity name="Address" representedClassName="Address" syncable="YES">'
            + '    <attribute name="street" optional="YES" attributeType="String"/>'
            + '    <relationship name="person" optional="YES" maxCount="1" deletionRule="Nullify"'
            + '                  destinationEntity="Person" inverseName="addresses" inverseEntity="Person"/>'
            + '  </entity>'
            + '</model>';

    var model = [CPManagedObjectModel _parseContentsXML:xml];

    [self assertNotNull:model message:@"model should not be nil"];
    [self assertNotNull:[model entityWithName:@"Person"]  message:@"Person entity missing"];
    [self assertNotNull:[model entityWithName:@"Address"] message:@"Address entity missing"];
}

- (void)testParseContentsXMLPersonAttributes
{
    if (typeof DOMParser === "undefined")
        return;

    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            + '<model type="com.apple.IDECoreDataModeler.DataModel">'
            + '  <entity name="Person" representedClassName="Person" syncable="YES">'
            + '    <attribute name="firstName" optional="YES" attributeType="String"/>'
            + '    <attribute name="age"       optional="NO"  attributeType="Integer 32" defaultValueString="0"/>'
            + '    <attribute name="isActive"  optional="YES" attributeType="Boolean"/>'
            + '    <attribute name="birthDate" optional="YES" attributeType="Date"/>'
            + '  </entity>'
            + '</model>';

    var model = [CPManagedObjectModel _parseContentsXML:xml];
    var entity = [model entityWithName:@"Person"];

    [self assertNotNull:entity message:@"Person entity missing"];
    [self assert:4 equals:[[entity propertyNames] count] message:@"should have 4 properties"];

    var attrs = [entity attributesByName];
    [self assertNotNull:[attrs objectForKey:@"firstName"] message:@"firstName attribute missing"];
    [self assertNotNull:[attrs objectForKey:@"age"]       message:@"age attribute missing"];
    [self assertNotNull:[attrs objectForKey:@"isActive"]  message:@"isActive attribute missing"];
    [self assertNotNull:[attrs objectForKey:@"birthDate"] message:@"birthDate attribute missing"];

    [self assert:CPDStringAttributeType
          equals:[[attrs objectForKey:@"firstName"] typeValue]
         message:@"firstName should be String type"];
    [self assert:CPDInteger32AttributeType
          equals:[[attrs objectForKey:@"age"] typeValue]
         message:@"age should be Integer32 type"];
    [self assert:CPDBooleanAttributeType
          equals:[[attrs objectForKey:@"isActive"] typeValue]
         message:@"isActive should be Boolean type"];
    [self assert:CPDDateAttributeType
          equals:[[attrs objectForKey:@"birthDate"] typeValue]
         message:@"birthDate should be Date type"];
}

- (void)testParseContentsXMLRelationships
{
    if (typeof DOMParser === "undefined")
        return;

    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            + '<model type="com.apple.IDECoreDataModeler.DataModel">'
            + '  <entity name="Person" representedClassName="Person" syncable="YES">'
            + '    <relationship name="addresses" optional="YES" toMany="YES" deletionRule="Cascade"'
            + '                  destinationEntity="Address" inverseName="person" inverseEntity="Address"/>'
            + '  </entity>'
            + '  <entity name="Address" representedClassName="Address" syncable="YES">'
            + '    <relationship name="person" optional="YES" maxCount="1" deletionRule="Nullify"'
            + '                  destinationEntity="Person" inverseName="addresses" inverseEntity="Person"/>'
            + '  </entity>'
            + '</model>';

    var model  = [CPManagedObjectModel _parseContentsXML:xml],
        person = [model entityWithName:@"Person"],
        addr   = [model entityWithName:@"Address"];

    [self assertNotNull:person message:@"Person entity missing"];
    [self assertNotNull:addr   message:@"Address entity missing"];

    var personRels = [person relationshipsByName],
        addrRels   = [addr   relationshipsByName];

    var addressesRel = [personRels objectForKey:@"addresses"];
    [self assertNotNull:addressesRel message:@"addresses relationship missing"];
    [self assertTrue:[addressesRel isToMany]      message:@"addresses should be to-many"];
    [self assert:@"Address"
          equals:[addressesRel destinationEntityName]
         message:@"addresses destination wrong"];
    [self assert:CPRelationshipDescriptionDeleteRuleCascade
          equals:[addressesRel deleteRule]
         message:@"addresses delete rule wrong"];

    var personRel = [addrRels objectForKey:@"person"];
    [self assertNotNull:personRel message:@"person relationship missing"];
    [self assertFalse:[personRel isToMany]        message:@"person should be to-one"];
    [self assert:CPRelationshipDescriptionDeleteRuleNullify
          equals:[personRel deleteRule]
         message:@"person delete rule wrong"];
}

- (void)testParseContentsXMLOptionalFlag
{
    if (typeof DOMParser === "undefined")
        return;

    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            + '<model type="com.apple.IDECoreDataModeler.DataModel">'
            + '  <entity name="Item" representedClassName="Item" syncable="YES">'
            + '    <attribute name="required" optional="NO"  attributeType="String"/>'
            + '    <attribute name="optional" optional="YES" attributeType="String"/>'
            + '  </entity>'
            + '</model>';

    var model  = [CPManagedObjectModel _parseContentsXML:xml],
        entity = [model entityWithName:@"Item"],
        attrs  = [entity attributesByName];

    [self assertFalse:[[attrs objectForKey:@"required"] isOptional]
              message:@"required should not be optional"];
    [self assertTrue:[[attrs objectForKey:@"optional"] isOptional]
              message:@"optional should be optional"];
}

@end
