// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UserNotifications/UserNotifications.h>
#endif

#import "MSChannelGroupProtocol.h"
#import "MSChannelUnitProtocol.h"
#import "MSDataStore.h"
#import "MSDataStoreInternal.h"
#import "MSTestFrameworks.h"
#import "MSUserIdContextPrivate.h"
#import "MSDataStore.h"
#import "MSSerializableDocument.h"
#import "MSDocumentWrapper.h"
#import "MSWriteOptions.h"
#import "MSPage.h"
#import "MSTokenExchange.h"
#import "MSTokensResponse.h"
#import "MSTokenResult.h"
#import "MSCosmosDb.h"

@interface MSDataStore (Test)

+ (instancetype)sharedInstance;

+ (void)createWithPartition:(NSString *)partition
                                documentId:(NSString *)documentId
                                document:(id<MSSerializableDocument>)document
                                completionHandler:(MSDocumentWrapperCompletionHandler)completionHandler;

+ (void)createWithPartition:(NSString *)partition
                                documentId:(NSString *)documentId
                                document:(id<MSSerializableDocument>)document
                                writeOptions:(MSWriteOptions *)writeOptions
                                completionHandler:(MSDocumentWrapperCompletionHandler)completionHandler;

+ (void)deleteDocumentWithPartition:(NSString *)partition
                                documentId:(NSString *)documentId
                                writeOptions:(MSWriteOptions *)__unused writeOptions
                                completionHandler:(MSDataSourceErrorCompletionHandler)completionHandler;
@end

@interface MSDataStoreTests : XCTestCase

@end

@implementation MSDataStoreTests

- (void)setUp {
  [super setUp];
}

- (void)tearDown {
  [super tearDown];
}

- (void)testCreateWithPartitionWithoutWriteOptionsGoldenTest {
    
    // If
    NSString *partition = @"partition";
    NSString *documentId = @"documentId";
    NSString *httpMethod = @"POST";
    NSData *body = nil;
    NSDictionary *additionalHeaders = nil;
    id mockSerializableDocument = OCMProtocolMock(@protocol(MSSerializableDocument));
    OCMStub([mockSerializableDocument serializeToDictionary]).andReturn([NSDictionary new]);

    // Mock tokens fetching.
    MSTokensResponse *testTokensResponse = [[MSTokensResponse alloc] initWithTokens:@[[MSTokenResult new]]];
    id tokenExchangeMock = OCMClassMock([MSTokenExchange class]);
    OCMStub([tokenExchangeMock performDbTokenAsyncOperationWithHttpClient:OCMOCK_ANY partition:OCMOCK_ANY completionHandler:OCMOCK_ANY])
        .andDo(^(NSInvocation *invocation) {
            MSGetTokenAsyncCompletionHandler getTokenCallback;
            [invocation retainArguments];
            [invocation getArgument:&getTokenCallback atIndex:4];
            getTokenCallback(testTokensResponse, nil);
        });

    // Mock CosmosDB requests.
    NSData *testResponse = nil;
    OCMStub([MSCosmosDb performCosmosDbAsyncOperationWithHttpClient:OCMOCK_ANY
                                                tokenResult:OCMOCK_ANY
                                                 documentId:documentId
                                                 httpMethod:httpMethod
                                                       body:body // we need to double check what body is allowed here, defined as nil for now
                                          additionalHeaders:additionalHeaders // the same for headers, but we have a reference here and need to check values using [OCMArg checkWithBlock]
                                          completionHandler:OCMOCK_ANY
    ]).andDo(^(NSInvocation *invocation) {
        MSCosmosDbCompletionHandler cosmosdbOperationCallback;
        [invocation retainArguments];
        [invocation getArgument:&getTokenCallback atIndex:8];
        cosmosdbOperationCallback(testResponse, nil);
    });

    //__block BOOL completionHandlerCalled = NO;
    __block XCTestExpectation *completeExpectation = [self expectationWithDescription:@"Task finished"];
    MSDocumentWrapperCompletionHandler completionHandler = ^(MSDocumentWrapper *data) {
        //completionHandlerCalled = YES;
        [completionHandler fulfill];
    };
    
    // When
    [MSDataStore createWithPartition:partition
                          documentId:documentId
                            document:mockSerializableDocument
                   completionHandler:completionHandler];

    // Then
    [self waitForExpectationsWithTimeout:5 handler:handler:^(NSError *error) {
        //XCTAssertTrue([completeExpectation assertForOverFulfill]);
        //XCTAssertTrue(completionHandlerCalled);
        if (error) {
          XCTFail(@"Expectation Failed with error: %@", error);
        }
    }];
}

- (void)testCreateWithPartitionWithWriteOptionsGoldenTest {
    
    //If
    NSString *partition = @"partition";
    NSString *documentId = @"documentId";
    MSWriteOptions *options = [MSWriteOptions new];
    
    id mockSerializableDocument = OCMProtocolMock(@protocol(MSSerializableDocument));
    OCMStub([mockSerializableDocument serializeToDictionary]).andReturn([NSDictionary new]);
    
    __block BOOL completionHandlerCalled = NO;
    XCTestExpectation *completeExpectation = [self expectationWithDescription:@"Task finished"];
    MSDocumentWrapperCompletionHandler completionHandler = ^(MSDocumentWrapper *data) {
        completionHandlerCalled = YES;
        [completionHandler fulfill];
    };
    
    // When
    [MSDataStore createWithPartition:partition
                          documentId:documentId
                            document:mockSerializableDocument
                        writeOptions:options
                   completionHandler:completionHandler];
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
    
    // Then
    XCTAssertTrue([completeExpectation assertForOverFulfill]);
    XCTAssertTrue(completionHandlerCalled);
    
}

- (void) testDeleteDocumentWithPartitionWithoutWriteOptions {
    
    // If
    NSString *partition = @"partition";
    NSString *documentId = @"documentId";
    
    __block BOOL completionHandlerCalled = NO;
    XCTestExpectation *completeExpectation = [self expectationWithDescription:@"Task finished"];
    MSDataSourceErrorCompletionHandler completionHandler = ^(MSDataSourceError *error) {
        completionHandlerCalled = YES;
        [completionHandler fulfill];
    };
    
    // When
    [MSDataStore deleteDocumentWithPartition:partition
                                            documentId:documentId
                                            completionHandler:completionHandler];
    
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
    
    // Then
    XCTAssertTrue([completeExpectation assertForOverFulfill]);
    XCTAssertTrue(completionHandlerCalled);
}

- (void) testDeleteDocumentWithPartitionWithWriteOptions {
    
    // If
    NSString *partition = @"partition";
    NSString *documentId = @"documentId";
    MSWriteOptions *options = [MSWriteOptions new];
    
    __block BOOL completionHandlerCalled = NO;
    XCTestExpectation *completeExpectation = [self expectationWithDescription:@"Task finished"];
    MSDataSourceErrorCompletionHandler completionHandler = ^(MSDataSourceError *error) {
        completionHandlerCalled = YES;
        [completionHandler fulfill];
    };
    
    // When
    [MSDataStore deleteDocumentWithPartition:partition
                                  documentId:documentId
                                writeOptions:options
                           completionHandler:completionHandler];
    
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
    
    // Then
    XCTAssertTrue([completeExpectation assertForOverFulfill]);
    XCTAssertTrue(completionHandlerCalled);
}
@end
