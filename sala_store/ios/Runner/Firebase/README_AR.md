# إعداد Firebase لتطبيق المتجر على iOS

لا تضع ملفاً من مشروع تطوير داخل أرشيف App Store.

- `dev/GoogleService-Info.plist`: تطبيق Firebase iOS ذو المعرّف
  `com.selafood.store.dev` في مشروع `salla-dev`.
- `prod/GoogleService-Info.plist`: تطبيق Firebase iOS ذو المعرّف
  `com.salllla.marchent` في مشروع `sela-food-prod`.

تختار مرحلة Xcode الملف تلقائياً: Debug للتطوير، وProfile/Release للإنتاج،
وتفشل مغلقة عند غياب الملف أو اختلاف المعرّف أو المشروع.
