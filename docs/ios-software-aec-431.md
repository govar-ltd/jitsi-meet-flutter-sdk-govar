# Эксперимент 431: software AEC

Основа приложения 430 (5bfe185), SDK 9412fac10aadd91774d044cb32d1ea6e33867b5e. Бэкап 430 в Бэкапы/До software AEC 431 2026-10-20, SHA256.json.

WebRTC Jitsi M124: e7fccf32f8833bbe66b9ffdb73e5990af0809840. Отдельная пересборка из исходников, без вмешательства в C++ ABI готового бинарника. На iOS audioSource получает ios_force_software_aec_HACK=true, echo_cancellation=true, NS/AGC/highpass=false. AGC2 выключен для этого экспериментального режима. Обход VoiceProcessingIO и непрерывная WAV запись из 430 сохраняются.

Новый callback logger сохраняет только счетчики двух заданных сообщений и ограниченную строку конфигурации APM, без SDP/токенов/пользовательских данных. Наличие сообщения Force software AEC означает выбор ветки движка; дополнительно проверить примененную конфигурацию aec=1 mobile=0 ns=0 agc1=0 agc2=0 hpf=0.

WebRTC собран из исходников: patched source 02a0e6af1e7d31da255ea2cab1630e0e7f79d983, Chromium build d95f411 (публичный путь SubFrameworks для ObjC под SDK 26). UUID 4C4C4426-5555-3144-A18E-C6F2124B39E7, SHA256 ce71817c53b3ce6b8f93599f6f43b1728ca32c5bd1daec329de6071c2fe7c96a. Маркеры двух правок и три системных импорта для bypass проверены. Полный LICENSE.md включён в resources SDK. Сборка приложения и установка пока не завершены. В сторы не отправлять. Телефон пока на 430. После сборки сравнить UUID WebRTC и встроенные маркеры с новым framework, после установки проверить версию устройства.
