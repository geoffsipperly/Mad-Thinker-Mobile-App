//
//  SkeenaSystemUITests.swift
//  SkeenaSystemUITests
//
//  Created by Geoff Sipperly on 1/14/26.
//

import XCTest

final class SkeenaSystemUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
               continueAfterFailure = false

               // Read DRY_RUN from the test environment (scheme Test > Arguments > Environment Variables)
               // Accepts "true" or "false" (case-insensitive). Default = false (perform actual reset).
               let env = ProcessInfo.processInfo.environment
               let dryRunRaw = env["DRY_RUN"] ?? "false"
               let dryRun = (dryRunRaw as NSString).boolValue

               // Create client (adjust timeout if your reset can be long)
               let client = ResetDatabaseClient(timeout: 120)

               do {
                   print("Calling reset-database (dryRun=\(dryRun))...")
                   let resp = try client.resetDatabaseBlocking(dryRun: dryRun, timeout: 120)
                   // Optionally assert/verify the response
                   if !resp.success {
                       XCTFail("Reset endpoint returned success = false (dryRun=\(resp.dryRun)) — response: \(resp)")
                   } else {
                       print("Reset succeeded: deleted \(resp.summary.totalDeleted ?? 0) rows across \(resp.summary.tablesProcessed ?? 0) tables")
                   }
               } catch {
                   // Fail the setup so tests don't run against an unknown DB state
                   XCTFail("Failed to reset test database: \(error.localizedDescription)")
               }

               // Continue with launching the app
               app = XCUIApplication()
               app.launchArguments += ["-uiTesting"]
               // optionally configure API base URL for your test server
               app.launchEnvironment["API_BASE_URL"] = "PLACEHOLDER_URL"
               app.launch()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }


    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testGuideLogin() throws {
        
    }
}

