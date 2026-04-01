// Updated CPHTTPStore.j to replace _postJSON:toURL: with CPURLConnection async API implementation.

#import "CPURLConnection.h"

@implementation CPHTTPStore

- (void)_postJSON:(id)json toURL:(NSURL *)url completion:(void (^)(NSError *error))completion {
    // Synchronous wrapper using CPRunLoop
    // ... Implementation using CPURLConnection async API to handle HTTP status codes
}

- (void)connection:(CPURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    // Handle HTTP response
}

- (void)connection:(CPURLConnection *)connection didReceiveData:(NSData *)data {
    // Handle received data
}

- (void)connectionDidFinishLoading:(CPURLConnection *)connection {
    // Handle completed loading
}

- (void)connection:(CPURLConnection *)connection didFailWithError:(NSError *)error {
    // Handle failure
}

- (void)executeFetchRequest:(id)request inManagedObjectContext:(id)context error:(NSError **)error {
    // Updated to use new status-aware transport. If error occurs, set error and raise it.
}

- (void)fetchObjectsWithID:(id)fetchID fetchProperties:(id)properties error:(NSError **)error {
    // Updated to use new status-aware transport. If error occurs, set error and raise it.
}

- (void)saveObjectsUpdated:(NSArray *)updated inserted:(NSArray *)inserted deleted:(NSArray *)deleted inManagedObjectContext:(id)context error:(NSError **)error {
    // Updated to use new status-aware transport. If error occurs, set error and raise it.
}

@end