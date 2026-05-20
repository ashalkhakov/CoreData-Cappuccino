//
//  CPMemoryStoreType.j
//
//  Created by Raphael Bartolome on 11.01.10.
//

@import <Foundation/CPObject.j>
@import "CPPersistentStoreType.j"

@class CPMemoryStore;

CPMemoryStoreConfigurationKeyResourcesFile = "CPMemoryStoreResourcesFile";
CPMemoryStoreConfigurationKeyFileFormat = "CPMemoryDAVStoreFileFormat";

@implementation CPMemoryStoreType : CPPersistentStoreType
{
}

+ (CPString)type
{
	return "CPMemoryStore";
}

+ (Class)storeClass
{
	return [CPMemoryStore class];
}

@end
