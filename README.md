# Finanças (automático via notificações) — Android

1. `./setup.sh`
2. `cd app && flutter run` (celular com depuração USB)
3. No app, toque no aviso amarelo e ative o acesso a notificações para "Finanças".

Como funciona: o serviço Kotlin guarda as notificações dos bancos numa fila; o app lê a fila ao abrir,
extrai valor/local, categoriza e salva no SQLite. Tocar num lançamento muda a categoria e o app aprende.

Ajustes: bancos em `BankNotificationService.kt`, regras de texto em `lib/parser.dart`.

## Gerar APK sem instalar nada (GitHub Actions)
1. Crie um repositório no GitHub e envie o conteúdo desta pasta (incluindo `.github`).
2. Aba **Actions** > "Build APK" > aguarde ~5 min.
3. Baixe o artefato `financas-apk`, extraia e instale o `app-release.apk` no celular.

## Atualziar o projeto
git add .

git commit -m "Descrição da atualização"

git push
