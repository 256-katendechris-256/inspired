# flutter_local_notifications stores scheduled notifications with Gson, which
# needs generic type signatures at runtime. R8 strips them from release builds,
# so without these rules the 08:45/09:00 sign-in reminders fail to schedule and
# the boot/update receiver that restores them crashes ("TypeToken must be
# created with a type argument"). Rules from the plugin's Android setup notes.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.** { *; }
