-keep class com.sec.app.** { *; }
-dontwarn org.json.**

# === ANDRO-R4T fix: regras keep ===
-keep class * extends android.app.Service { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends android.app.Activity { *; }
-keep class * extends android.content.ContentProvider { *; }
-keep class * implements android.os.Parcelable { *; }
-keep class * implements java.io.Serializable { *; }
-keepclasseswithmembers class * {
    public static void main(java.lang.String[]);
}
-keepattributes Signature, InnerClasses, EnclosingMethod,\
                RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
