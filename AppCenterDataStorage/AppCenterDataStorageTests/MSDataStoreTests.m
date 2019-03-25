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
    
    //If
    NSString *partition = @"partition";
    NSString *documentId = @"documentId";
   
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
                   completionHandler:completionHandler];
    
    [self waitForExpectationsWithTimeout:5 handler:nil];
    
    // Then
    XCTAssertTrue([completeExpectation assertForOverFulfill]);
    XCTAssertTrue(completionHandlerCalled);
    
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
