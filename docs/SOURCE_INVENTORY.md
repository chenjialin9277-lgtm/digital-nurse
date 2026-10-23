# Development file inventory

Date: 2026-10-23. Current source, tests, platform projects and archived upstream materials are retained. Asset checksums are in `asset-manifest.json`.

## Module counts

| Directory | Tracked files |
| --- | ---: |
| `lib/` | 58 |
| `test/` | 31 |
| `tool/` | 1 |
| `android/` | 36 |
| `packages/` | 8 |
| `ios/` | 49 |
| `macos/` | 29 |
| `linux/` | 7 |
| `windows/` | 15 |
| `web/` | 6 |
| `docs/archive/` | 38 |

## lib/

| File | Lines / bytes |
| --- | ---: |
| `lib/controllers/nurse_controller.dart` | 805 lines |
| `lib/features/education/controllers/education_session_controller.dart` | 323 lines |
| `lib/features/education/data/default_education_items.dart` | 263 lines |
| `lib/features/education/data/education_analytics_service.dart` | 39 lines |
| `lib/features/education/data/education_event_repository.dart` | 7 lines |
| `lib/features/education/data/education_repository.dart` | 21 lines |
| `lib/features/education/data/education_rollback_snapshot.dart` | 41 lines |
| `lib/features/education/data/legacy_education_migrator.dart` | 100 lines |
| `lib/features/education/data/native_education_event_repository.dart` | 45 lines |
| `lib/features/education/data/native_education_repository.dart` | 81 lines |
| `lib/features/education/models/comprehension_result.dart` | 31 lines |
| `lib/features/education/models/education_analytics_summary.dart` | 100 lines |
| `lib/features/education/models/education_item.dart` | 209 lines |
| `lib/features/education/models/education_language_content.dart` | 121 lines |
| `lib/features/education/models/education_session_event.dart` | 103 lines |
| `lib/features/education/screens/bedside_education_screen.dart` | 313 lines |
| `lib/features/education/screens/education_playback_screen.dart` | 789 lines |
| `lib/features/education/services/education_translation_service.dart` | 97 lines |
| `lib/features/education/widgets/comprehension_card.dart` | 90 lines |
| `lib/features/education/widgets/comprehension_question_editor.dart` | 204 lines |
| `lib/features/education/widgets/daily_language_selector.dart` | 54 lines |
| `lib/features/education/widgets/education_catalog.dart` | 342 lines |
| `lib/features/education/widgets/education_feedback_card.dart` | 94 lines |
| `lib/features/education/widgets/education_item_editor.dart` | 289 lines |
| `lib/features/education/widgets/education_management_dialog.dart` | 360 lines |
| `lib/features/education/widgets/language_content_editor.dart` | 151 lines |
| `lib/features/education/widgets/video_education_item_editor.dart` | 300 lines |
| `lib/main.dart` | 69 lines |
| `lib/models/app_usage_record.dart` | 52 lines |
| `lib/models/nurse_app_config.dart` | 346 lines |
| `lib/models/offline_speech_language.dart` | 24 lines |
| `lib/repositories/app_usage_repository.dart` | 75 lines |
| `lib/repositories/nurse_config_repository.dart` | 113 lines |
| `lib/screens/nurse_screen.dart` | 1157 lines |
| `lib/services/department_logo_service.dart` | 11 lines |
| `lib/services/education_video_service.dart` | 23 lines |
| `lib/services/local_speech_event.dart` | 1 lines |
| `lib/services/local_speech_service.dart` | 25 lines |
| `lib/services/microphone_capture_result.dart` | 60 lines |
| `lib/services/network_monitor.dart` | 17 lines |
| `lib/services/nurse_avatar_image_service.dart` | 11 lines |
| `lib/services/offline_multilingual_tts.dart` | 544 lines |
| `lib/services/offline_speech_cache.dart` | 153 lines |
| `lib/services/offline_speech_segmenter.dart` | 61 lines |
| `lib/services/online_audio_prebuffer.dart` | 42 lines |
| `lib/services/online_playback_gate.dart` | 46 lines |
| `lib/services/push_to_talk_audio_session.dart` | 65 lines |
| `lib/services/usage_export_service.dart` | 159 lines |
| `lib/services/xiaozhi_provisioning_service.dart` | 156 lines |
| `lib/services/xiaozhi_service.dart` | 904 lines |
| `lib/services/xiaozhi_websocket_manager.dart` | 413 lines |
| `lib/theme/nurse_theme.dart` | 177 lines |
| `lib/utils/audio_util.dart` | 372 lines |
| `lib/utils/diagnostic_log.dart` | 7 lines |
| `lib/widgets/nurse_avatar.dart` | 236 lines |
| `lib/widgets/nurse_config_dialog.dart` | 762 lines |
| `lib/widgets/settings_password_dialog.dart` | 72 lines |
| `lib/widgets/usage_records_dialog.dart` | 464 lines |

## test/

| File | Lines / bytes |
| --- | ---: |
| `test/avatar_preview_test.dart` | 85 lines |
| `test/features/education/bedside_education_screen_test.dart` | 377 lines |
| `test/features/education/education_analytics_service_test.dart` | 165 lines |
| `test/features/education/education_event_repository_test.dart` | 73 lines |
| `test/features/education/education_export_test.dart` | 140 lines |
| `test/features/education/education_item_test.dart` | 132 lines |
| `test/features/education/education_management_dialog_test.dart` | 288 lines |
| `test/features/education/education_playback_screen_test.dart` | 804 lines |
| `test/features/education/education_repository_test.dart` | 144 lines |
| `test/features/education/education_rollback_snapshot_test.dart` | 36 lines |
| `test/features/education/education_session_controller_test.dart` | 211 lines |
| `test/features/education/education_test_fixtures.dart` | 75 lines |
| `test/features/education/education_translation_service_test.dart` | 54 lines |
| `test/features/education/education_upgrade_integration_test.dart` | 704 lines |
| `test/features/education/education_widget_harness.dart` | 26 lines |
| `test/features/education/fake_education_event_repository.dart` | 26 lines |
| `test/features/education/fake_education_repository.dart` | 64 lines |
| `test/features/education/legacy_education_migrator_test.dart` | 62 lines |
| `test/services/microphone_capture_result_test.dart` | 60 lines |
| `test/services/offline_speech_cache_test.dart` | 82 lines |
| `test/services/offline_speech_segmenter_test.dart` | 67 lines |
| `test/services/online_audio_prebuffer_test.dart` | 35 lines |
| `test/services/online_playback_gate_test.dart` | 76 lines |
| `test/services/push_to_talk_audio_session_test.dart` | 44 lines |
| `test/services/xiaozhi_service_audio_error_test.dart` | 74 lines |
| `test/utils/audio_util_test.dart` | 40 lines |
| `test/widget_test.dart` | 747 lines |

## tool/

| File | Lines / bytes |
| --- | ---: |
| `tool/verify_offline_tts.dart` | 67 lines |

## packages/

| File | Lines / bytes |
| --- | ---: |
| `packages/flutter_pcm_player/LICENSE` | 19 lines |
| `packages/flutter_pcm_player/android/build.gradle` | 18 lines |
| `packages/flutter_pcm_player/android/settings.gradle` | 1 lines |
| `packages/flutter_pcm_player/android/src/main/AndroidManifest.xml` | 1 lines |
| `packages/flutter_pcm_player/android/src/main/java/com/example/flutter_pcm_player/FlutterPcmPlayerPlugin.java` | 69 lines |
| `packages/flutter_pcm_player/android/src/main/java/com/example/flutter_pcm_player/PcmPlayer.java` | 107 lines |
| `packages/flutter_pcm_player/lib/flutter_pcm_player.dart` | 75 lines |
| `packages/flutter_pcm_player/pubspec.yaml` | 19 lines |

## android/

| File | Lines / bytes |
| --- | ---: |
| `android/.gitignore` | 11 lines |
| `android/app/build.gradle.kts` | 96 lines |
| `android/app/proguard-rules.pro` | 31 lines |
| `android/app/src/debug/AndroidManifest.xml` | 7 lines |
| `android/app/src/main/AndroidManifest.xml` | 59 lines |
| `android/app/src/main/kotlin/com/digitalnurse/app/EducationDatabaseChannel.kt` | 124 lines |
| `android/app/src/main/kotlin/com/digitalnurse/app/EducationDatabaseHelper.kt` | 321 lines |
| `android/app/src/main/kotlin/com/digitalnurse/app/EducationVideoActivity.kt` | 122 lines |
| `android/app/src/main/kotlin/com/digitalnurse/app/MainActivity.kt` | 717 lines |
| `android/app/src/main/kotlin/com/digitalnurse/app/UsageXlsxWriter.kt` | 187 lines |
| `android/app/src/main/res/drawable-hdpi/ic_launcher_foreground.png` | 4915 bytes |
| `android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png` | 3306 bytes |
| `android/app/src/main/res/drawable-v21/launch_background.xml` | 12 lines |
| `android/app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png` | 6185 bytes |
| `android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png` | 13784 bytes |
| `android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png` | 20673 bytes |
| `android/app/src/main/res/drawable/launch_background.xml` | 12 lines |
| `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` | 9 lines |
| `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` | 2229 bytes |
| `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` | 1408 bytes |
| `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` | 2830 bytes |
| `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` | 4176 bytes |
| `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` | 5460 bytes |
| `android/app/src/main/res/values-night/styles.xml` | 18 lines |
| `android/app/src/main/res/values/colors.xml` | 4 lines |
| `android/app/src/main/res/values/styles.xml` | 18 lines |
| `android/app/src/profile/AndroidManifest.xml` | 7 lines |
| `android/app/src/test/kotlin/com/digitalnurse/app/UsageXlsxWriterTest.kt` | 58 lines |
| `android/build.gradle.kts` | 21 lines |
| `android/gradle.properties` | 8 lines |
| `android/gradle/wrapper/gradle-wrapper.jar` | 53636 bytes |
| `android/gradle/wrapper/gradle-wrapper.properties` | 5 lines |
| `android/gradlew` | 160 lines |
| `android/gradlew.bat` | 90 lines |
| `android/key.properties.example` | 6 lines |
| `android/settings.gradle.kts` | 26 lines |

## Additional scope

- `.github/`, `scripts/`, root configuration and dependency lock files.
- 405 assets (270,141,867 bytes), including images, three speech models, original design materials and historical 3D resources. Four ONNX/GLB files use Git LFS.
- All 18 JS/MJS resources passed syntax checks; vendored code is preserved.
- Other platform folders are retained upstream scaffolds, without current cross-platform acceptance.
- Historical website source is under `docs/archive/upstream/website/`; generated caches are excluded.
- Use `git ls-files` for the full checkout inventory, and `git lfs ls-files` for LFS objects.

## Local-only materials

Signing keys, credentials, SDKs, dependency caches, build output, duplicate model archives, old APKs and backups containing signing materials remain local and are excluded from this repository.
