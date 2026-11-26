import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release (FIRMA-01): los datos viven en android/key.properties, que nunca se versiona
// (ver android/key.properties.example y docs/FIRMA_Y_EMPAQUETADO.md). El keystore vive fuera del repo.
val keystorePropertiesFile = rootProject.file("key.properties")
val hayFirmaRelease = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hayFirmaRelease) keystorePropertiesFile.inputStream().use { load(it) }
}

fun claveFirma(nombre: String): String =
    keystoreProperties.getProperty(nombre)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("Falta \"$nombre\" en android/key.properties (ver android/key.properties.example).")

android {
    namespace = "com.utez.safelink"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.utez.safelink"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayFirmaRelease) {
            create("release") {
                keyAlias = claveFirma("keyAlias")
                keyPassword = claveFirma("keyPassword")
                storeFile = file(claveFirma("storeFile"))
                storePassword = claveFirma("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Sin key.properties (p. ej. en la computadora de un compañero) se firma con la llave
            // debug para que `flutter run --release` siga funcionando. Ese APK NO se entrega.
            signingConfig = if (hayFirmaRelease) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "ADVERTENCIA SafeLink: no existe android/key.properties; el release se firma con la " +
                        "llave DEBUG y no sirve para entregar. Ver docs/FIRMA_Y_EMPAQUETADO.md.",
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
