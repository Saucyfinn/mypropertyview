# 🚀 PropertyMapApp - Fresh Start Setup

**Simple, minimal iOS app focused on getting LINZ API working in Xcode**

## 📱 Quick Setup

1. **Open PropertyMapApp.xcodeproj in Xcode**
2. **Add your LINZ API key to Info.plist:**
   - Open `PropertyMapApp/Info.plist`
   - Find `<key>LINZ_API_KEY</key>`
   - Replace `PUT_YOUR_LINZ_API_KEY_HERE` with your actual API key
3. **Build & Run**

## 🔍 Testing

The app will:
- ✅ Show a map of Wellington
- ✅ Display API key status in top-left corner
- ✅ Auto-test LINZ API on startup
- ✅ Draw property boundaries in blue
- 🔵 "Test LINZ API" button for manual testing

## 🔧 Debugging

Check Xcode console for logs:
- `🔑 LINZ API Key from Bundle: 'LOADED (32 chars)'` ✅ Good
- `🔑 LINZ API Key from Bundle: 'EMPTY'` ❌ Key not configured
- `✅ LINZ API SUCCESS! Got X parcels` ✅ API working
- `❌ LINZ API ERROR: 401` ❌ Invalid API key

## 🎯 Key Difference from Previous Version

- **Simplified architecture** - No complex AR or multi-tab setup
- **Direct API key injection** - Loads from Info.plist immediately
- **Comprehensive logging** - See exactly what's happening
- **Minimal dependencies** - Just Leaflet + LINZ API

This should work immediately once you add your LINZ API key to Info.plist!