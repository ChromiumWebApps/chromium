// Copyright (c) 2010 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Cocoa/Cocoa.h>
#include <vector>

#include "base/ref_counted_memory.h"
#include "base/string_util.h"
#include "base/sys_string_conversions.h"
#include "chrome/app/chrome_dll_resource.h"
#include "chrome/browser/browser.h"
#include "chrome/browser/cancelable_request.h"
#include "chrome/browser/cocoa/browser_test_helper.h"
#include "chrome/browser/cocoa/cocoa_test_helper.h"
#include "chrome/browser/cocoa/history_menu_bridge.h"
#include "chrome/browser/sessions/tab_restore_service.h"
#include "gfx/codec/png_codec.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"

namespace {

class MockTRS : public TabRestoreService {
 public:
  MockTRS(Profile* profile) : TabRestoreService(profile, NULL) {}
  MOCK_CONST_METHOD0(entries, const TabRestoreService::Entries&());
};

class MockBridge : public HistoryMenuBridge {
 public:
  MockBridge(Profile* profile)
      : HistoryMenuBridge(profile),
        menu_([[NSMenu alloc] initWithTitle:@"History"]) {}

  virtual NSMenu* HistoryMenu() {
    return menu_.get();
  }

 private:
  scoped_nsobject<NSMenu> menu_;
};

class HistoryMenuBridgeTest : public CocoaTest {
 public:

  virtual void SetUp() {
    CocoaTest::SetUp();
    browser_test_helper_.profile()->CreateFaviconService();
    bridge_.reset(new MockBridge(browser_test_helper_.profile()));
  }

  // We are a friend of HistoryMenuBridge (and have access to
  // protected methods), but none of the classes generated by TEST_F()
  // are. Wraps common commands.
  void ClearMenuSection(NSMenu* menu,
                        NSInteger tag) {
    bridge_->ClearMenuSection(menu, tag);
  }

  void AddItemToBridgeMenu(HistoryMenuBridge::HistoryItem* item,
                           NSMenu* menu,
                           NSInteger tag,
                           NSInteger index) {
    bridge_->AddItemToMenu(item, menu, tag, index);
  }

  NSMenuItem* AddItemToMenu(NSMenu* menu,
                            NSString* title,
                            SEL selector,
                            int tag) {
    NSMenuItem* item = [[[NSMenuItem alloc] initWithTitle:title action:NULL
                                            keyEquivalent:@""] autorelease];
    [item setTag:tag];
    if (selector) {
      [item setAction:selector];
      [item setTarget:bridge_->controller_.get()];
    }
    [menu addItem:item];
    return item;
  }

  HistoryMenuBridge::HistoryItem* CreateItem(const string16& title) {
    HistoryMenuBridge::HistoryItem* item =
        new HistoryMenuBridge::HistoryItem();
    item->title = title;
    item->url = GURL(title);
    return item;
  }

  MockTRS::Tab CreateSessionTab(const GURL& url, const string16& title) {
    MockTRS::Tab tab;
    tab.current_navigation_index = 0;
    tab.navigations.push_back(
        TabNavigation(0, url, GURL(), title, std::string(),
                      PageTransition::LINK));
    return tab;
  }

  void GetFaviconForHistoryItem(HistoryMenuBridge::HistoryItem* item) {
    bridge_->GetFaviconForHistoryItem(item);
  }

  void GotFaviconData(FaviconService::Handle handle,
                      bool know_favicon,
                      scoped_refptr<RefCountedBytes> data,
                      bool expired,
                      GURL url) {
    bridge_->GotFaviconData(handle, know_favicon, data, expired, url);
  }

  CancelableRequestConsumerTSimple<HistoryMenuBridge::HistoryItem*>&
      favicon_consumer() {
    return bridge_->favicon_consumer_;
  }

  BrowserTestHelper browser_test_helper_;
  scoped_ptr<MockBridge> bridge_;
};

// Edge case test for clearing until the end of a menu.
TEST_F(HistoryMenuBridgeTest, ClearHistoryMenuUntilEnd) {
  NSMenu* menu = [[[NSMenu alloc] initWithTitle:@"history foo"] autorelease];
  AddItemToMenu(menu, @"HEADER", NULL, HistoryMenuBridge::kMostVisitedTitle);

  NSInteger tag = HistoryMenuBridge::kMostVisited;
  AddItemToMenu(menu, @"alpha", @selector(openHistoryMenuItem:), tag);
  AddItemToMenu(menu, @"bravo", @selector(openHistoryMenuItem:), tag);
  AddItemToMenu(menu, @"charlie", @selector(openHistoryMenuItem:), tag);
  AddItemToMenu(menu, @"delta", @selector(openHistoryMenuItem:), tag);

  ClearMenuSection(menu, HistoryMenuBridge::kMostVisited);

  EXPECT_EQ(1, [menu numberOfItems]);
  EXPECT_TRUE([@"HEADER" isEqualToString:
      [[menu itemWithTag:HistoryMenuBridge::kMostVisitedTitle] title]]);
}

// Skip menu items that are not hooked up to |-openHistoryMenuItem:|.
TEST_F(HistoryMenuBridgeTest, ClearHistoryMenuSkipping) {
  NSMenu* menu = [[[NSMenu alloc] initWithTitle:@"history foo"] autorelease];
  AddItemToMenu(menu, @"HEADER", NULL, HistoryMenuBridge::kMostVisitedTitle);

  NSInteger tag = HistoryMenuBridge::kMostVisited;
  AddItemToMenu(menu, @"alpha", @selector(openHistoryMenuItem:), tag);
  AddItemToMenu(menu, @"bravo", @selector(openHistoryMenuItem:), tag);
  AddItemToMenu(menu, @"TITLE", NULL, HistoryMenuBridge::kRecentlyClosedTitle);
  AddItemToMenu(menu, @"charlie", @selector(openHistoryMenuItem:), tag);

  ClearMenuSection(menu, tag);

  EXPECT_EQ(2, [menu numberOfItems]);
  EXPECT_TRUE([@"HEADER" isEqualToString:
      [[menu itemWithTag:HistoryMenuBridge::kMostVisitedTitle] title]]);
  EXPECT_TRUE([@"TITLE" isEqualToString:
      [[menu itemAtIndex:1] title]]);
}

// Edge case test for clearing an empty menu.
TEST_F(HistoryMenuBridgeTest, ClearHistoryMenuEmpty) {
  NSMenu* menu = [[[NSMenu alloc] initWithTitle:@"history foo"] autorelease];
  AddItemToMenu(menu, @"HEADER", NULL, HistoryMenuBridge::kMostVisited);

  ClearMenuSection(menu, HistoryMenuBridge::kMostVisited);

  EXPECT_EQ(1, [menu numberOfItems]);
  EXPECT_TRUE([@"HEADER" isEqualToString:
      [[menu itemWithTag:HistoryMenuBridge::kMostVisited] title]]);
}

// Test that AddItemToMenu() properly adds HistoryItem objects as menus.
TEST_F(HistoryMenuBridgeTest, AddItemToMenu) {
  NSMenu* menu = [[[NSMenu alloc] initWithTitle:@"history foo"] autorelease];

  const string16 short_url = ASCIIToUTF16("http://foo/");
  const string16 long_url = ASCIIToUTF16("http://super-duper-long-url--."
      "that.cannot.possibly.fit.even-in-80-columns"
      "or.be.reasonably-displayed-in-a-menu"
      "without.looking-ridiculous.com/"); // 140 chars total

  // HistoryItems are owned by the HistoryMenuBridge when AddItemToBridgeMenu()
  // is called, which places them into the |menu_item_map_|, which owns them.
  HistoryMenuBridge::HistoryItem* item1 = CreateItem(short_url);
  AddItemToBridgeMenu(item1, menu, 100, 0);

  HistoryMenuBridge::HistoryItem* item2 = CreateItem(long_url);
  AddItemToBridgeMenu(item2, menu, 101, 1);

  EXPECT_EQ(2, [menu numberOfItems]);

  EXPECT_EQ(@selector(openHistoryMenuItem:), [[menu itemAtIndex:0] action]);
  EXPECT_EQ(@selector(openHistoryMenuItem:), [[menu itemAtIndex:1] action]);

  EXPECT_EQ(100, [[menu itemAtIndex:0] tag]);
  EXPECT_EQ(101, [[menu itemAtIndex:1] tag]);

  // Make sure a short title looks fine
  NSString* s = [[menu itemAtIndex:0] title];
  EXPECT_EQ(base::SysNSStringToUTF16(s), short_url);

  // Make sure a super-long title gets trimmed
  s = [[menu itemAtIndex:0] title];
  EXPECT_TRUE([s length] < long_url.length());

  // Confirm tooltips and confirm they are not trimmed (like the item
  // name might be).  Add tolerance for URL fixer-upping;
  // e.g. http://foo becomes http://foo/)
  EXPECT_GE([[[menu itemAtIndex:0] toolTip] length], (2*short_url.length()-5));
  EXPECT_GE([[[menu itemAtIndex:1] toolTip] length], (2*long_url.length()-5));
}

// Test that the menu is created for a set of simple tabs.
TEST_F(HistoryMenuBridgeTest, RecentlyClosedTabs) {
  scoped_refptr<MockTRS> trs(new MockTRS(browser_test_helper_.profile()));
  MockTRS::Entries entries;

  MockTRS::Tab tab1 = CreateSessionTab(GURL("http://google.com"),
                                       ASCIIToUTF16("Google"));
  tab1.id = 24;
  entries.push_back(&tab1);

  MockTRS::Tab tab2 = CreateSessionTab(GURL("http://apple.com"),
                                       ASCIIToUTF16("Apple"));
  tab2.id = 42;
  entries.push_back(&tab2);

  using ::testing::ReturnRef;
  EXPECT_CALL(*trs.get(), entries()).WillOnce(ReturnRef(entries));

  bridge_->TabRestoreServiceChanged(trs.get());

  NSMenu* menu = bridge_->HistoryMenu();
  ASSERT_EQ(2U, [[menu itemArray] count]);

  NSMenuItem* item1 = [menu itemAtIndex:0];
  MockBridge::HistoryItem* hist1 = bridge_->HistoryItemForMenuItem(item1);
  EXPECT_TRUE(hist1);
  EXPECT_EQ(24, hist1->session_id);
  EXPECT_TRUE([@"Google" isEqualToString:[item1 title]]);

  NSMenuItem* item2 = [menu itemAtIndex:1];
  MockBridge::HistoryItem* hist2 = bridge_->HistoryItemForMenuItem(item2);
  EXPECT_TRUE(hist2);
  EXPECT_EQ(42, hist2->session_id);
  EXPECT_TRUE([@"Apple" isEqualToString:[item2 title]]);
}

// Test that the menu is created for a mix of windows and tabs.
TEST_F(HistoryMenuBridgeTest, RecentlyClosedTabsAndWindows) {
  scoped_refptr<MockTRS> trs(new MockTRS(browser_test_helper_.profile()));
  MockTRS::Entries entries;

  MockTRS::Tab tab1 = CreateSessionTab(GURL("http://google.com"),
                                       ASCIIToUTF16("Google"));
  tab1.id = 24;
  entries.push_back(&tab1);

  MockTRS::Window win1;
  win1.id = 30;
  win1.tabs.push_back(
      CreateSessionTab(GURL("http://foo.com"), ASCIIToUTF16("foo")));
  win1.tabs[0].id = 31;
  win1.tabs.push_back(
      CreateSessionTab(GURL("http://bar.com"), ASCIIToUTF16("bar")));
  win1.tabs[1].id = 32;
  entries.push_back(&win1);

  MockTRS::Tab tab2 = CreateSessionTab(GURL("http://apple.com"),
                                       ASCIIToUTF16("Apple"));
  tab2.id = 42;
  entries.push_back(&tab2);

  MockTRS::Window win2;
  win2.id = 50;
  win2.tabs.push_back(
      CreateSessionTab(GURL("http://magic.com"), ASCIIToUTF16("magic")));
  win2.tabs[0].id = 51;
  win2.tabs.push_back(
      CreateSessionTab(GURL("http://goats.com"), ASCIIToUTF16("goats")));
  win2.tabs[1].id = 52;
  win2.tabs.push_back(
      CreateSessionTab(GURL("http://teleporter.com"),
                       ASCIIToUTF16("teleporter")));
  win2.tabs[1].id = 53;
  entries.push_back(&win2);

  using ::testing::ReturnRef;
  EXPECT_CALL(*trs.get(), entries()).WillOnce(ReturnRef(entries));

  bridge_->TabRestoreServiceChanged(trs.get());

  NSMenu* menu = bridge_->HistoryMenu();
  ASSERT_EQ(4U, [[menu itemArray] count]);

  NSMenuItem* item1 = [menu itemAtIndex:0];
  MockBridge::HistoryItem* hist1 = bridge_->HistoryItemForMenuItem(item1);
  EXPECT_TRUE(hist1);
  EXPECT_EQ(24, hist1->session_id);
  EXPECT_TRUE([@"Google" isEqualToString:[item1 title]]);

  NSMenuItem* item2 = [menu itemAtIndex:1];
  MockBridge::HistoryItem* hist2 = bridge_->HistoryItemForMenuItem(item2);
  EXPECT_TRUE(hist2);
  EXPECT_EQ(30, hist2->session_id);
  EXPECT_EQ(2U, hist2->tabs.size());
  // Do not test menu item title because it is localized.
  NSMenu* submenu1 = [item2 submenu];
  EXPECT_EQ(4U, [[submenu1 itemArray] count]);
  // Do not test Restore All Tabs because it is localiced.
  EXPECT_TRUE([[submenu1 itemAtIndex:1] isSeparatorItem]);
  EXPECT_TRUE([@"foo" isEqualToString:[[submenu1 itemAtIndex:2] title]]);
  EXPECT_TRUE([@"bar" isEqualToString:[[submenu1 itemAtIndex:3] title]]);

  NSMenuItem* item3 = [menu itemAtIndex:2];
  MockBridge::HistoryItem* hist3 = bridge_->HistoryItemForMenuItem(item3);
  EXPECT_TRUE(hist3);
  EXPECT_EQ(42, hist3->session_id);
  EXPECT_TRUE([@"Apple" isEqualToString:[item3 title]]);

  NSMenuItem* item4 = [menu itemAtIndex:3];
  MockBridge::HistoryItem* hist4 = bridge_->HistoryItemForMenuItem(item4);
  EXPECT_TRUE(hist4);
  EXPECT_EQ(50, hist4->session_id);
  EXPECT_EQ(3U, hist4->tabs.size());
  // Do not test menu item title because it is localized.
  NSMenu* submenu2 = [item4 submenu];
  EXPECT_EQ(5U, [[submenu2 itemArray] count]);
  // Do not test Restore All Tabs because it is localiced.
  EXPECT_TRUE([[submenu2 itemAtIndex:1] isSeparatorItem]);
  EXPECT_TRUE([@"magic" isEqualToString:[[submenu2 itemAtIndex:2] title]]);
  EXPECT_TRUE([@"goats" isEqualToString:[[submenu2 itemAtIndex:3] title]]);
  EXPECT_TRUE([@"teleporter" isEqualToString:[[submenu2 itemAtIndex:4] title]]);
}

// Tests that we properly request an icon from the FaviconService.
TEST_F(HistoryMenuBridgeTest, GetFaviconForHistoryItem) {
  // Create a fake item.
  HistoryMenuBridge::HistoryItem item;
  item.title = ASCIIToUTF16("Title");
  item.url = GURL("http://google.com");

  // Request the icon.
  GetFaviconForHistoryItem(&item);

  // Make sure that there is ClientData for the request.
  std::vector<HistoryMenuBridge::HistoryItem*> data;
  favicon_consumer().GetAllClientData(&data);
  ASSERT_EQ(data.size(), 1U);
  EXPECT_EQ(&item, data[0]);

  // Make sure the item was modified properly.
  EXPECT_TRUE(item.icon_requested);
  EXPECT_GT(item.icon_handle, 0);
}

TEST_F(HistoryMenuBridgeTest, GotFaviconData) {
  // Create a dummy bitmap.
  SkBitmap bitmap;
  bitmap.setConfig(SkBitmap::kARGB_8888_Config, 25, 25);
  bitmap.allocPixels();
  bitmap.eraseRGB(255, 0, 0);

  // Convert it to raw PNG bytes. We totally ignore color order here because
  // we just want to test the roundtrip through the Bridge, not that we can
  // make icons look pretty.
  std::vector<unsigned char> raw;
  gfx::PNGCodec::EncodeBGRASkBitmap(bitmap, true, &raw);
  scoped_refptr<RefCountedBytes> bytes(new RefCountedBytes(raw));

  // Set up the HistoryItem.
  HistoryMenuBridge::HistoryItem item;
  item.menu_item.reset([[NSMenuItem alloc] init]);
  GetFaviconForHistoryItem(&item);

  // Pretend to be called back.
  GotFaviconData(item.icon_handle, true, bytes, false, GURL());

  // Make sure the callback works.
  EXPECT_EQ(false, item.icon_requested);
  EXPECT_TRUE(item.icon.get());
  EXPECT_TRUE([item.menu_item image]);
}

}  // namespace
