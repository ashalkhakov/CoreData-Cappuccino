//
//  CPWebDAVStoreType.j
//
//  Created by Raphael Bartolome on 10.01.10.
//

@import <Foundation/Foundation.j>
@import "CPPersistentStoreType.j"

@class CPWebDAVStore;

CPWebDAVStoreConfigurationKeyBaseURL = "CPWebDAVStoreBaseURL";
CPWebDAVStoreConfigurationKeyFilePath = "CPWebDAVStoreFilePath";
CPWebDAVStoreConfigurationKeyFileFormat = "CPWebDAVStoreFileFormat";


@implementation CPWebDAVStoreType : CPPersistentStoreType
{
}

+ (CPString)type
{
	return "CPWebDAVStore";
}

+ (Class)storeClass
{
	return [CPWebDAVStore class];
}

@end
