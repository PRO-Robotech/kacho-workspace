# kacho-workspace — корневой Makefile.
.PHONY: vault-sync

# vault-sync — стянуть архитектурную доку (docs/arch/) всех сервисов
# из project/* в Obsidian-vault obsidian/kacho/<repo>/arch/ (read-only агрегат).
vault-sync:
	./scripts/vault-sync.sh
