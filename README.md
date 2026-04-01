[xcode-template]: http://github.com/rbartolome/xcode-cappuccino

# How to use CoreData for Cappuccino #
Just copy the CoreData folder to your Project Frameworks folder and import the Framework in you Application Delegate file.

	#import <CoreData/CoreData.j>  

# Data Model #

## 1. Supported Data Model Formats ##
- CoreData - *.xcdatamodel (Cocoa Model File Format)
- EOModel - *.eomodeld (WebObjects Model File Format)

## 2. How to load a Data Model ##
The Data Model file must be stored in your Project `Resources` folder.

CoreData:

	var model = [CPManagedObjectModel modelWithModelNamed:@"YourModelFile.xcdatamodel" bundle:nil];

EOModel:

	var model = [CPManagedObjectModel modelWithModelNamed:@"YourModelFile.eomodeld" bundle:nil];
  
## 3. How to Compile and Convert a CoreData Model for Cappuccino ##
*This instruction is not necessary if you use the latest [Xcode Cappuccino Templates][xcode-template].*  
  

1. Your .xcdatamodel file location should be the Project Resources folder

2. Open a Terminal and switch to the Project Resources folder.

3. Compile the .xcdatamodel file with momc    

	`/Developer/usr/bin/momc source.xcdatamodel target.cxcdatamodel`  
  
	The compiled file suffix is .cxcdatamodel

4. Transform the binary formatted file into xml   
	(I work on a binary parser for Cappuccino but until I am finish this step is necessary)  
	  
	`plutil -convert xml1 target.cxcdatamodel`
	
	
# Persistant Store #

Every store depends on two parts: 

1. Type Class: This should be named as the store plus a name suffix 'Type'.  
*For Example: CPWebDAVStore.j and the Type class is CPWebDAVStoreType.j*
2. Configuration Dictionary. This dictionary defines the configuration for the store.  
*For Example see the 'CPWebDAVStore Configuration Dictionary' section*

## 1. Available stores ##
### CPWebDAVStore ###
**Configuration Dictionary:**

1. 	*Key:* CPWebDAVStoreConfigurationKeyBaseURL  
	*Object:* is the base URL for exp.: `@"http://localhost:8080"`  
	
2. 	*Key:* CPWebDAVStoreConfigurationKeyFilePath  
	*Object:*  file path/name.suffix exp.: `@"addressbook.json"`
	
3. 	*Key:* CPWebDAVStoreConfigurationKeyFileFormat  
	*Object:* The format of your store exp.:  
	`CPCoreDataSerializationJSONFormat || CPCoreDataSerializationXMLFormat || CPCoreDataSerialization280NPLISTFormat`

**Implementation:**
You can see a demo for this in the Addressbook Example ABContextController.j Class.

	- (id) initWithContext
	{
		if(self = [super init])
		{
			//load your model file
			var model = [CPManagedObjectModel modelWithModelNamed:@"AddressBook.xcdatamodel" bundle:nil];
			var coordinator = [[CPPersistentStoreCoordinator alloc] 
										initWithManagedObjectModel:model 
														 storeType:[CPWebDAVStoreType class] 
												storeConfiguration:[ABContextController webDAVConfig]];

			//init the context with the coordinator
			context = [[CPManagedObjectContext alloc] initWithPersistantStoreCoordinator: coordinator];
			[context setAutoSaveChanges:YES];
																				 	
		}
	
		return self;
	}

	+ (CPDictionary) webDAVConfig
	{
		var result = [[CPMutableDictionary alloc] init];

		[result setObject:@"http://localhost:8080" forKey:CPWebDAVStoreConfigurationKeyBaseURL];
		[result setObject:@"addressbook.json" forKey:CPWebDAVStoreConfigurationKeyFilePath];
		[result setObject:CPCoreDataSerializationJSONFormat forKey:CPWebDAVStoreConfigurationKeyFileFormat];

		return result
	}

**Using the Addressbook Application Example:**  
If you have no WebDAV Server running I recommend [jack-dav](http://github.com/tlrobinson/jack-dav) for Testing.
The Example work also without a server, in this case the data will store in memory

**Notes:**  
Currently accessing a user/password protected webdav is not supported, If you know how, please write me a mail.

### CPWOStore ###
*!!! Currently not up-to-date with the latest implementation, I work on a update for both client and server side !!!*

### CPHTTPIncrementalStore ###
An incremental HTTP store that talks to the **OrderFlow OrdersAPI** backend via two
JSON endpoints: `/cdFetch` (read) and `/cdSave` (write).  Unlike the bulk stores
(WebDAV, HTML5) this store never loads all objects at initialisation time; data is
fetched on demand as the application executes fetch requests or traverses
relationships.

**Configuration Dictionary:**

1. *Key:* `CPHTTPIncrementalStoreConfigurationKeyBaseURL`
   *Object:* Base URL of the OrdersAPI, e.g. `@"http://localhost:8080/api/"`.
   A trailing slash is added automatically if missing.

**Setting up the store:**

	- (id)initWithContext
	{
	    if (self = [super init])
	    {
	        var model = [CPManagedObjectModel modelWithModelNamed:@"Orders.xcdatamodel" bundle:nil];
	        var config = [[CPMutableDictionary alloc] init];
	        [config setObject:@"http://localhost:8080/api/"
	                   forKey:CPHTTPIncrementalStoreConfigurationKeyBaseURL];

	        var coordinator = [[CPPersistentStoreCoordinator alloc]
	                               initWithManagedObjectModel:model
	                                                storeType:[CPHTTPIncrementalStoreType class]
	                                        storeConfiguration:config];

	        _context = [[CPManagedObjectContext alloc]
	                        initWithPersistantStoreCoordinator:coordinator];
	    }
	    return self;
	}

**Fetching objects:**

Fetch requests work just like other stores.  To pass a server-side predicate use
a `CPDictionary` containing the server AST directly:

	var request = [[CPFetchRequest alloc] init];
	[request setEntity:[[_context model] entityWithName:@"Customer"]];
	[request setPredicate:[CPDictionary dictionaryWithJSObject:
	    {op:"beginswith", key:"fullName", value:"I"} recursively:YES]];
	[request setFetchLimit:10];

	var results = [_context executeFetchRequest:request error:nil];

**Saving objects:**

Use the standard `saveChanges:` call on the context.  Newly inserted objects
receive their permanent server IDs via the `idMap` in the `/cdSave` response.

	[_context saveChanges:nil];

**Backend contract (summary):**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/cdFetch` | POST | Fetch objects (graph or IDs-only mode) |
| `/cdSave`  | POST | Insert / update / delete objects |

Global IDs stored in `CPManagedObjectID.globalID` use the format
`"EntityName|pkKey1=jsonVal1;pkKey2=jsonVal2;"` (pk keys sorted alphabetically),
which is stable and reversible.

## 2. Write your own Persistant Store ##
