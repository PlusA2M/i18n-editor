//
//  PermissionManagerTests.swift
//  i18n editor
//
//  Created by PlusA on 17/07/2025.
//

import XCTest
@testable import i18n_editor

class PermissionManagerTests: XCTestCase {
    var permissionManager: PermissionManager!
    
    override func setUp() {
        super.setUp()
        permissionManager = PermissionManager()
    }
    
    override func tearDown() {
        permissionManager = nil
        super.tearDown()
    }
    
    func testPermissionManagerInitialization() {
        XCTAssertNotNil(permissionManager)
        XCTAssertFalse(permissionManager.showingPermissionAlert)
        XCTAssertEqual(permissionManager.permissionAlertMessage, "")
    }
    
    func testCheckFullDiskAccess() {
        // This test will vary based on the actual system permissions
        let hasAccess = permissionManager.checkFullDiskAccess()
        
        // We can't assert a specific value since it depends on system state
        // But we can verify the method doesn't crash and returns a boolean
        XCTAssertTrue(hasAccess == true || hasAccess == false)
    }
    
    func testCanAccessProjectPath() {
        // Test with a path that should be accessible (user's home directory)
        let homePath = NSHomeDirectory()
        let canAccess = permissionManager.canAccessProject(at: homePath)
        
        // Should be able to access home directory
        XCTAssertTrue(canAccess)
    }
    
    func testCanAccessNonExistentPath() {
        // Test with a non-existent path
        let nonExistentPath = "/this/path/does/not/exist"
        let canAccess = permissionManager.canAccessProject(at: nonExistentPath)
        
        // Should not be able to access non-existent path
        XCTAssertFalse(canAccess)
    }
}

// MARK: - TableEditingStateManager Tests

class TableEditingStateManagerTests: XCTestCase {
    var editingStateManager: TableEditingStateManager!
    
    override func setUp() {
        super.setUp()
        editingStateManager = TableEditingStateManager()
    }
    
    override func tearDown() {
        editingStateManager = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertFalse(editingStateManager.isInEditMode)
        XCTAssertNil(editingStateManager.currentEditingCell)
        XCTAssertTrue(editingStateManager.pendingChanges.isEmpty)
    }
    
    func testEnterEditMode() {
        let position = TableEditingStateManager.CellPosition(
            keyId: UUID(),
            locale: "en",
            rowIndex: 0,
            columnIndex: 0
        )
        
        let expectation = XCTestExpectation(description: "Edit mode should be entered")
        
        editingStateManager.enterEditMode(at: position)
        
        // Since enterEditMode now uses DispatchQueue.main.async, we need to wait
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.editingStateManager.isInEditMode)
            XCTAssertEqual(self.editingStateManager.currentEditingCell, position)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testExitEditMode() {
        let position = TableEditingStateManager.CellPosition(
            keyId: UUID(),
            locale: "en",
            rowIndex: 0,
            columnIndex: 0
        )
        
        let expectation = XCTestExpectation(description: "Edit mode should be exited")
        
        // First enter edit mode
        editingStateManager.enterEditMode(at: position)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Then exit edit mode
            self.editingStateManager.exitEditMode()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertFalse(self.editingStateManager.isInEditMode)
                XCTAssertNil(self.editingStateManager.currentEditingCell)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testNavigateToCell() {
        let position1 = TableEditingStateManager.CellPosition(
            keyId: UUID(),
            locale: "en",
            rowIndex: 0,
            columnIndex: 0
        )
        
        let position2 = TableEditingStateManager.CellPosition(
            keyId: UUID(),
            locale: "fr",
            rowIndex: 1,
            columnIndex: 1
        )
        
        let expectation = XCTestExpectation(description: "Should navigate to new cell")
        
        editingStateManager.navigateToCell(position1)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.editingStateManager.currentEditingCell, position1)
            
            self.editingStateManager.navigateToCell(position2)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertEqual(self.editingStateManager.currentEditingCell, position2)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
}
