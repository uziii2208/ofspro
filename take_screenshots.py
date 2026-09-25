import os
import time
from playwright.sync_api import sync_playwright

IMAGES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "images")
os.makedirs(IMAGES_DIR, exist_ok=True)

def capture_showcase():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        # High-DPI viewport (1600x950 with 1.5 scale factor = 2400x1425 retina crispness)
        context = browser.new_context(
            viewport={"width": 1600, "height": 950},
            device_scale_factor=1.5
        )
        page = context.new_page()
        
        print("Navigating to http://127.0.0.1:8081/ ...")
        # Use domcontentloaded because /api/stream is a persistent SSE connection
        page.goto("http://127.0.0.1:8081/", wait_until="domcontentloaded")
        page.wait_for_selector(".feed-container", timeout=10000)
        time.sleep(2)  # Allow SSE and initial fetches to populate

        # 1. Main Live Interceptor Tab
        print("Capturing image_01.png (Main Live Interceptor)...")
        page.screenshot(path=os.path.join(IMAGES_DIR, "image_01.png"), full_page=False)

        # 2. Open Sliding Drawer on a flow (if flows exist)
        inspect_btns = page.locator(".inspect-btn")
        if inspect_btns.count() > 0:
            print("Opening Inspect Drawer on first flow...")
            inspect_btns.first.click()
            time.sleep(1.0)
            print("Capturing image_02.png (Sliding Inspect Drawer)...")
            page.screenshot(path=os.path.join(IMAGES_DIR, "image_02.png"), full_page=False)
            
            # Close drawer
            page.locator("#drawerCloseBtn").click()
            time.sleep(0.5)

        # 3. Bypass Engine Tab
        print("Switching to Bypass Engine Tab...")
        page.locator("#tabBypass").click()
        time.sleep(1.0)
        print("Capturing showcase_bypass.png...")
        page.screenshot(path=os.path.join(IMAGES_DIR, "showcase_bypass.png"), full_page=False)

        # 4. Localhost Lures Tab
        print("Switching to Localhost Lures Tab...")
        page.locator("#tabLures").click()
        time.sleep(1.0)
        print("Capturing showcase_lures.png...")
        page.screenshot(path=os.path.join(IMAGES_DIR, "showcase_lures.png"), full_page=False)

        # 5. Deception Lab (Playground)
        print("Switching to Deception Lab Tab...")
        page.locator("#tabPlayground").click()
        time.sleep(1.0)
        
        # Click a sample prompt chip and simulate
        sample_chips = page.locator(".sample-prompt-chip")
        if sample_chips.count() > 0:
            sample_chips.first.click()
            time.sleep(0.5)
            page.locator("#testPromptBtn").click()
            time.sleep(1.5)
            
        print("Capturing showcase_playground.png...")
        page.screenshot(path=os.path.join(IMAGES_DIR, "showcase_playground.png"), full_page=False)

        # 6. Terminal Logs Tab
        print("Switching to Terminal Tab...")
        page.locator("#tabTerminal").click()
        time.sleep(1.0)
        print("Capturing showcase_terminal.png...")
        page.screenshot(path=os.path.join(IMAGES_DIR, "showcase_terminal.png"), full_page=False)

        browser.close()
        print("All screenshots successfully captured!")

if __name__ == "__main__":
    capture_showcase()
