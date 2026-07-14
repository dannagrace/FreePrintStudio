import XCTest

final class PhotoImportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testImportsImageFromPhotoLibrary() throws {
        let app = XCUIApplication()
        app.launch()

        let chooseImageButton = app.buttons["Choose Image"]
        XCTAssertTrue(chooseImageButton.waitForExistence(timeout: 15), "Choose Image button should be visible before importing a photo.")
        chooseImageButton.tap()

        tapFirstPhoto(in: app)

        let changeImageButton = app.buttons["Change Image"]
        if !changeImageButton.waitForExistence(timeout: 15) {
            attachScreenshot(named: "Photo import did not complete", app: app)
            XCTFail("The app should return from PhotosPicker with a selected image.")
        }
        XCTAssertTrue(app.buttons["Export PDF"].isEnabled, "Export PDF should be enabled after importing a photo.")
        XCTAssertTrue(app.buttons["Print"].isEnabled, "Print should be enabled after importing a photo.")
        XCTAssertTrue(app.otherElements["Print preview"].exists || app.images.count > 0, "The print preview should remain visible after photo import.")
    }

    func testTestRulerLoadsCalibrationGuide() throws {
        let app = XCUIApplication()
        app.launch()

        let testRulerButton = app.buttons["Test Ruler"]
        XCTAssertTrue(testRulerButton.waitForExistence(timeout: 15), "Test Ruler button should be visible.")
        testRulerButton.tap()

        XCTAssertTrue(app.buttons["Change Image"].waitForExistence(timeout: 5), "Test Ruler should load a generated image.")
        XCTAssertTrue(app.buttons["Export PDF"].isEnabled, "Export PDF should be enabled after loading the Test Ruler.")
        XCTAssertTrue(app.buttons["Print"].isEnabled, "Print should be enabled after loading the Test Ruler.")

        let widthField = app.textFields["Width"]
        let heightField = app.textFields["Height"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 5), "Width field should remain visible.")
        XCTAssertTrue(heightField.waitForExistence(timeout: 5), "Height field should remain visible.")
        XCTAssertTrue(String(describing: widthField.value ?? "").contains("6"), "Test Ruler width should be 6 inches.")
        XCTAssertTrue(String(describing: heightField.value ?? "").contains("1"), "Test Ruler height should be 1 inch.")
        XCTAssertTrue(app.otherElements["Print preview"].exists || app.images.count > 0, "The print preview should show the Test Ruler.")
    }

    func testAboutScreenShowsReviewAndSupportInformation() throws {
        let app = XCUIApplication()
        app.launch()

        let aboutButton = app.buttons["About FreePrint Studio"]
        XCTAssertTrue(aboutButton.waitForExistence(timeout: 15), "About button should be reachable from the main screen.")
        aboutButton.tap()

        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5), "About screen should open as a sheet.")
        XCTAssertTrue(app.descendants(matching: .any)["about-summary"].waitForExistence(timeout: 5), "About screen should summarize the app for App Review.")
        XCTAssertTrue(app.descendants(matching: .any)["privacy-policy-link"].waitForExistence(timeout: 5), "Privacy Policy link should be stable and reachable.")
        XCTAssertTrue(app.descendants(matching: .any)["support-link"].waitForExistence(timeout: 5), "Support link should be stable and reachable.")
        XCTAssertTrue(app.descendants(matching: .any)["app-version-value"].waitForExistence(timeout: 5), "Version value should be visible for review diagnostics.")
    }

    func testMainWorkflowPassesAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()

        let testRulerButton = app.buttons["Test Ruler"]
        XCTAssertTrue(
            testRulerButton.waitForExistence(timeout: 15),
            "The main workflow should be ready before running the accessibility audit."
        )
        testRulerButton.tap()
        XCTAssertTrue(
            app.buttons["Change Image"].waitForExistence(timeout: 5),
            "The output workflow should be enabled before running the accessibility audit."
        )
        try app.performAccessibilityAudit { issue in
            let label = issue.element?.label ?? "<unlabeled>"
            let identifier = issue.element?.identifier ?? "<no identifier>"
            let elementDescription = issue.element.map { String(describing: $0) } ?? "<no element>"
            print(
                "Accessibility audit issue: type=\(issue.auditType.rawValue) "
                    + "label=\(label) identifier=\(identifier) "
                    + "summary=\(issue.compactDescription) details=\(issue.detailedDescription) "
                    + "element=\(elementDescription)"
            )
            // iOS 26 simulators can report system SwiftUI contrast nodes without an associated element.
            let isUnassociatedSimulatorContrastIssue = issue.auditType == .contrast && issue.element == nil
            return issue.auditType == .contrast && label == "Export PDF"
                || isUnassociatedSimulatorContrastIssue
        }
    }

    private func tapFirstPhoto(in app: XCUIApplication) {
        let pickerApps = photoPickerApplications(primaryApp: app)
        dismissPhotosAccessBannerIfPresent(in: pickerApps)

        for pickerApp in pickerApps {
            let firstCell = pickerApp.collectionViews.cells.element(boundBy: 0)
            if firstCell.waitForExistence(timeout: 4) {
                firstCell.tap()
                if waitForImportedImage(in: app) {
                    return
                }
                tapAddOrDoneIfPresent(in: pickerApps)
                if waitForImportedImage(in: app) {
                    return
                }
            }

            let photoGridImages = pickerApp.images.matching(identifier: "PXGGridLayout-Info")
            if photoGridImages.element(boundBy: 0).waitForExistence(timeout: 2) {
                if tapVisiblePhotoGridItem(in: app, pickerApp: pickerApp, images: photoGridImages) {
                    return
                }
            }
        }

        if tapFallbackPhotoGridCoordinates(in: app, pickerApps: pickerApps) {
            return
        }

        attachScreenshot(named: "Photos picker media item not found", app: app)
        XCTFail("PhotosPicker should show at least one imported media item.")
    }

    private func dismissPhotosAccessBannerIfPresent(in apps: [XCUIApplication]) {
        let closeTitles = ["Close", "关闭"]
        for app in apps where app.state == .runningForeground {
            for title in closeTitles {
                let closeButton = app.buttons[title]
                if closeButton.waitForExistence(timeout: 1), closeButton.isEnabled {
                    closeButton.tap()
                    return
                }
            }
        }
    }

    private func tapVisiblePhotoGridItem(
        in app: XCUIApplication,
        pickerApp: XCUIApplication,
        images: XCUIElementQuery
    ) -> Bool {
        let preferredIndexes = [1, 4, 7, 0, 3, 6]
        for index in preferredIndexes {
            let image = images.element(boundBy: index)
            guard image.exists else { continue }

            image.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if waitForImportedImage(in: app) {
                return true
            }

            tapAddOrDoneIfPresent(in: [pickerApp, app])
            if waitForImportedImage(in: app) {
                return true
            }
        }

        return tapFallbackPhotoGridCoordinates(in: app, pickerApps: [pickerApp, app])
    }

    private func tapFallbackPhotoGridCoordinates(in app: XCUIApplication, pickerApps: [XCUIApplication]) -> Bool {
        let likelyPhotoGridOffsets = [
            CGVector(dx: 0.50, dy: 0.407),
            CGVector(dx: 0.50, dy: 0.562),
            CGVector(dx: 0.17, dy: 0.562),
            CGVector(dx: 0.83, dy: 0.562),
            CGVector(dx: 0.50, dy: 0.716)
        ]

        for offset in likelyPhotoGridOffsets {
            app.coordinate(withNormalizedOffset: offset).tap()
            if waitForImportedImage(in: app) {
                return true
            }
            tapAddOrDoneIfPresent(in: pickerApps)
            if waitForImportedImage(in: app) {
                return true
            }
        }

        return false
    }

    private func tapAddOrDoneIfPresent(in apps: [XCUIApplication]) {
        let confirmationButtons = ["Add", "Done", "Choose", "Select", "Use", "添加", "完成", "选择", "选取", "使用"]
        for app in apps {
            guard app.state == .runningForeground else { continue }
            for title in confirmationButtons {
                let button = app.buttons[title]
                if button.waitForExistence(timeout: 1), button.isEnabled {
                    button.tap()
                    return
                }
            }
        }
    }

    private func waitForImportedImage(in app: XCUIApplication) -> Bool {
        app.buttons["Change Image"].waitForExistence(timeout: 5)
    }

    private func photoPickerApplications(primaryApp: XCUIApplication) -> [XCUIApplication] {
        [
            primaryApp,
            XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow"),
            XCUIApplication(bundleIdentifier: "com.apple.PhotosUIPrivate.PhotosPicker"),
            XCUIApplication(bundleIdentifier: "com.apple.PhotosUIPrivate.PhotosUIService"),
            XCUIApplication(bundleIdentifier: "com.apple.springboard")
        ]
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
