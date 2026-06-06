---
name: api-network-subnet
description: Паттерны use-case + handler структуры для Network и Subnet (kacho-vpc, Wave 5 pilot/replicate)
metadata:
  type: pattern
  phase: Wave 5 (KAC-94)
  scope: "CQRS Repository + Operation async + Outbox atomic + UpdateMask discipline"
---

# api/network + api/subnet — паттерны кодинга

**Фаза:** Wave 5 pilot (Network) и Wave 5 replicate (Subnet).  
**Скоуп:** Use-case+Handler архитектура, CQRS-Repository, Operation async-worker, Outbox emit, UpdateMask discipline, Error mapping.

---

## Файл: network/handler.go

### Что делает
Реализация gRPC-сервиса `vpcv1.NetworkServiceServer`. Тонкий transport-слой, без бизнес-логики: proto-request → domain → use-case → proto-response.

### Сигнатуры публичных функций

```go
// NewHandler собирает Handler из готовых use-case'ов
func NewHandler(
	create *CreateNetworkUseCase,
	update *UpdateNetworkUseCase,
	deleteUC *DeleteNetworkUseCase,
	move *MoveNetworkUseCase,
	get *GetNetworkUseCase,
	list *ListNetworksUseCase,
	listSubnets *ListSubnetsUseCase,
	listSG *ListSecurityGroupsUseCase,
	listRT *ListRouteTablesUseCase,
	listOps *ListOperationsUseCase,
) *Handler

// Get — sync read + AuthZ (folder ownership)
func (h *Handler) Get(ctx context.Context, req *vpcv1.GetNetworkRequest) (*vpcv1.Network, error)

// Create — AuthZ → domain → use-case → Operation proto
func (h *Handler) Create(ctx context.Context, req *vpcv1.CreateNetworkRequest) (*operationpb.Operation, error)

// Update — sync repo.Get для AuthZ, затем use-case
func (h *Handler) Update(ctx context.Context, req *vpcv1.UpdateNetworkRequest) (*operationpb.Operation, error)

// Delete — sync repo.Get для AuthZ, затем use-case
func (h *Handler) Delete(ctx context.Context, req *vpcv1.DeleteNetworkRequest) (*operationpb.Operation, error)

// (Move — удалён в KAC-266; ниже §5 сохранён как historical пример dual-AuthZ паттерна)
```

### Паттерны в handler.go

#### 1. Composition-root инъекция всех use-case'ов
Handler не создаёт use-case'ы — они injected в конструктор. Это позволяет:
- Composition root в `cmd/vpc/main.go` создаёт all use-case'ы с одинаковыми зависимостями (repo/projectClient/opsRepo)
- Unit-тесты легко мокировать каждый use-case

#### 2. AuthZ через AssertFolderOwnership
```go
func (h *Handler) Get(ctx context.Context, req *vpcv1.GetNetworkRequest) (*vpcv1.Network, error) {
	if req.NetworkId == "" {
		return nil, status.Error(codes.InvalidArgument, "network_id required")
	}
	n, err := h.get.Execute(ctx, req.NetworkId)
	if err != nil {
		return nil, err
	}
	if err := handler.AssertFolderOwnership(ctx, n.FolderID); err != nil {
		return nil, err
	}
	return networkToPb(n)
}
```

**Паттерн:** Чтение ресурса, затем синхронная проверка folder-ownership из context JWT.

#### 3. DTO-трансфер через blank-import
```go
import (
	_ "github.com/PRO-Robotech/kacho-vpc/internal/dto/toproto"  // регистрирует Network→proto, Subnet→proto, time→timestamppb
)

func networkToPb(rec *kachorepo.NetworkRecord) (*vpcv1.Network, error) {
	var dst *vpcv1.Network
	if err := dto.Transfer(dto.FromTo(*rec, &dst)); err != nil {
		return nil, status.Error(codes.Internal, "dto.Transfer Network failed")
	}
	return dst, nil
}
```

**Паттерн:** Реестр DTO-трансферов регистрируется через blank-import; `dto.Transfer` делает конверсию по registered converter'ам. Nil-error только при unknown type → логика не имеет альтернатив, поэтому `codes.Internal` (никогда не должно быть).

#### 4. Proto-конверсия в handler (не в use-case)
```go
func (h *Handler) Create(ctx context.Context, req *vpcv1.CreateNetworkRequest) (*operationpb.Operation, error) {
	if err := handler.AssertFolderOwnership(ctx, req.FolderId); err != nil {
		return nil, err
	}
	n := domain.Network{  // Proto fields → domain.Network
		FolderID:    req.FolderId,
		Name:        domain.RcNameVPC(req.Name),        // proto string → domain.RcNameVPC (newtype)
		Description: domain.RcDescription(req.Description),
		Labels:      domain.LabelsFromMap(req.Labels),  // proto map → domain.Labels
	}
	op, err := h.create.Execute(ctx, n)  // Передаём domain-модель, не proto
	if err != nil {
		return nil, err
	}
	return operationToProto(op), nil  // Operation → operationpb.Operation
}
```

**Паттерн:** Handler отвечает за proto↔domain конверсию. Use-case работает с domain-моделями. Proto string → domain newtype (RcNameVPC, RcDescription) прямо в handler, валидация потом в use-case/domain.

#### 5. Move semantics — двойная AuthZ (historical — RPC удалён в KAC-266)

> [!warning] `Move` удалён в [[../../KAC/KAC-266]]
> RPC `NetworkService.Move` (и Move у других vpc-ресурсов) снят (contract-removal). Пример ниже
> оставлен как archeology dual-AuthZ паттерна — он больше **не** соответствует живому коду.

```go
func (h *Handler) Move(ctx context.Context, req *vpcv1.MoveNetworkRequest) (*operationpb.Operation, error) {
	if req.NetworkId == "" {
		return nil, status.Error(codes.InvalidArgument, "network_id required")
	}
	n, err := h.get.Execute(ctx, req.NetworkId)
	if err != nil {
		return nil, err
	}
	// Проверяем, что caller владеет SOURCE folder'ом
	if err := handler.AssertFolderOwnership(ctx, n.FolderID); err != nil {
		return nil, err
	}
	// Проверяем, что caller владеет DESTINATION folder'ом
	if err := handler.AssertFolderOwnership(ctx, req.DestinationFolderId); err != nil {
		return nil, err
	}
	op, err := h.move.Execute(ctx, req.NetworkId, req.DestinationFolderId)
	if err != nil {
		return nil, err
	}
	return operationToProto(op), nil
}
```

**Паттерн:** Move требует AuthZ на обе папки (source и dest) перед отправкой в use-case. Use-case повторяет существование dest-folder'а в async-части как backstop.

#### 6. Child-list с parent-ownership-check
```go
func (h *Handler) ListSubnets(ctx context.Context, req *vpcv1.ListNetworkSubnetsRequest) (*vpcv1.ListNetworkSubnetsResponse, error) {
	if req.NetworkId == "" {
		return nil, status.Error(codes.InvalidArgument, "network_id required")
	}
	n, err := h.get.Execute(ctx, req.NetworkId)  // Получить parent
	if err != nil {
		return nil, err
	}
	if err := handler.AssertFolderOwnership(ctx, n.FolderID); err != nil {
		return nil, err
	}
	// Теперь безопасно листить children
	subs, nextToken, err := h.listSubnets.Execute(ctx, req.NetworkId, Pagination{...})
	// ...
}
```

**Паттерн:** Перед листингом children — получить parent, проверить ownership parent'а, потом листить children. Parent может быть NotFound → вернём NotFound перед auth-check.

---

## Файл: network/create.go

### Что делает
CreateNetworkUseCase инициирует создание Network:
- SYNC-часть: валидация, folder-name-uniqueness-check (в Reader-TX), создание Operation
- ASYNC-часть (worker): project existence check (`projectClient.Exists`, peer = kacho-iam), Network Insert, inline default-SG creation (опционально), outbox emit

### Сигнатуры

```go
// NewCreateNetworkUseCase создаёт CreateNetworkUseCase
func NewCreateNetworkUseCase(r Repo, projectClient ProjectClient, opsRepo operations.Repo, defaultSGInline bool) *CreateNetworkUseCase

// Execute — sync-валидация + Operation + запуск worker'а
func (u *CreateNetworkUseCase) Execute(ctx context.Context, n domain.Network) (*operations.Operation, error)

// doCreate — async-часть; атомарный backstop через FK/UNIQUE + outbox emit
func (u *CreateNetworkUseCase) doCreate(ctx context.Context, netID string, n domain.Network) (*anypb.Any, error)
```

### Паттерны в create.go

#### 1. Domain-Model Input (не CreateInput обёртка)
```go
// Execute принимает domain.Network напрямую (KAC-94, skill evgeniy §7 I.1)
func (u *CreateNetworkUseCase) Execute(ctx context.Context, n domain.Network) (*operations.Operation, error) {
	if n.FolderID == "" {
		return nil, status.Error(codes.InvalidArgument, "folder_id required")
	}
	if err := n.Validate(); err != nil {
		return nil, err
	}
	// ...
}
```

**Паттерн:** Тривиальная `CreateInput{Network: n}` обёртка удалена. Если контекста нет (всё параметры в domain-модели), передаём domain.X напрямую. Параметры, которые не в domain-модели (UpdateMask) → остаются в отдельном Xxx Input типе (см. UpdateInput в update.go).

#### 2. Sync-валидация до создания Operation
```go
// Проверяем name uniqueness в Reader-TX перед Operation
name := string(n.Name)
if name != "" {
	rd, err := u.repo.Reader(ctx)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	existing, _, lerr := rd.Networks().List(ctx, NetworkFilter{FolderID: n.FolderID, Name: name}, Pagination{})
	_ = rd.Close()
	if lerr != nil {
		return nil, mapRepoErr(lerr)
	}
	if len(existing) > 0 {
		return nil, status.Errorf(codes.AlreadyExists, "Network with name %s already exists", name)
	}
}
```

**Паттерн:**
- **Sync project.Exists check УДАЛЁН** (KAC-94 I.4): race-prone между check и async. Project может быть удалён peer-сервисом (kacho-iam). Проверка теперь только в async `doCreate` → `projectClient.Exists` → если не существует → `NotFound` в operation.error. (Peer переехал rm→iam в KAC-106; колонка `folder_id` = id владельца-проекта, legacy-имя.)
- **Sync name-uniqueness остаётся** (в Reader-TX): это race-free против peer-сервиса (уникальность в нашей БД). После uniqueness-check → тут же создаём Operation.
- Читаем в Reader-TX, закрываем перед Operation.Create (not holding transaction).

#### 3. Operation создание + async запуск
```go
netID := ids.NewID(ids.PrefixNetwork)  // Генерируем id использовать в async
op, err := operations.New(
	ids.PrefixOperationVPC,
	fmt.Sprintf("Create network %s", name),
	&vpcv1.CreateNetworkMetadata{NetworkId: netID},
)
if err != nil {
	return nil, err
}
if err := u.opsRepo.Create(ctx, op); err != nil {
	return nil, err
}

// Запуск worker'а (async)
operations.Run(ctx, u.opsRepo, op.ID, func(ctx context.Context) (*anypb.Any, error) {
	return u.doCreate(ctx, netID, n)
})

return &op, nil  // Возвращаем Operation (указатель)
```

**Паттерн:**
- ID генерируем в Execute (хотя он потребуется в async doCreate) → он в metadata Operation'а → клиент знает id заранее.
- `operations.New(prefix, description, metadata)` → Operation структура.
- `opsRepo.Create(ctx, op)` → сохранить Operation в БД.
- `operations.Run(ctx, opsRepo, op.ID, workerFunc)` → запустить goroutine с worker'ом.
- Worker будет обновлять Operation.Done/Error/Result и вызовет opsRepo.Update от имени текущего пакета (generic от kacho-corelib).

#### 4. Атомарная Writer-TX: Insert Network + inline SG + Commit/Abort
```go
func (u *CreateNetworkUseCase) doCreate(ctx context.Context, netID string, n domain.Network) (*anypb.Any, error) {
	// projectClient → kacho-iam.ProjectService.Get (peer переехал rm→iam, KAC-106).
	// n.ProjectID хранится в DB-колонке folder_id (legacy-имя). Текст ошибки "Folder..." оставлен для YC parity.
	exists, err := u.projectClient.Exists(ctx, n.ProjectID)
	if err != nil {
		return nil, status.Errorf(codes.Unavailable, "folder check: %v", err)
	}
	if !exists {
		return nil, status.Errorf(codes.NotFound, "Folder with id %s not found", n.ProjectID)
	}

	n.ID = netID

	w, err := u.repo.Writer(ctx)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	defer w.Abort()  // На любой return (nil или error) → Abort; Commit ниже переопределит

	created, err := w.Networks().Insert(ctx, &n)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	if err := w.Outbox().Emit(ctx, "Network", created.ID, "CREATED", networkPayloadMap(created)); err != nil {
		return nil, mapRepoErr(fmt.Errorf("%w: outbox emit: %v", repo.ErrInternal, err))
	}

	finalRec := created
	if u.defaultSGInline {
		// Composition use-case'ов в одной TX (skill evgeniy I.9-residual)
		upd, sgErr := u.createDefaultSG.Execute(ctx, w, created.Network)
		if sgErr != nil {
			return nil, sgErr  // defer w.Abort() ловит
		}
		finalRec = upd  // Network с заполненным default_sg_id
	}

	if err := w.Commit(); err != nil {
		return nil, mapRepoErr(err)
	}
	return marshalNetworkRecord(finalRec)
}
```

**Паттерн:**
- `w, err := u.repo.Writer(ctx)` → открыть Writer-TX.
- `defer w.Abort()` → на любом error (или panic) → откатить TX.
- DML (Insert, SetCidrBlocks, SetDefaultSGID, etc.) в TX.
- Outbox emit в той же TX → atomicity DML + notification.
- Если есть inline-операция (default SG) → вызвать её use-case в ОТКРЫТОЙ TX (use-case не открывает свою TX, работает в нашей) → она добавит свои DML + outbox в нашу TX.
- `w.Commit()` → ВСЕТ DML+outbox видны, триггер `vpc_outbox_notify_trg` → pg_notify.
- Return `marshalNetworkRecord(finalRec)` → завёрнуть domain-модель в `*anypb.Any` (для Operation.response).

#### 5. Error mapping через mapRepoErr
```go
if err := u.opsRepo.Create(ctx, op); err != nil {
	return nil, err  // Может быть уникальность Operation.id — маловероятно, но пробиваем
}

created, err := w.Networks().Insert(ctx, &n)
if err != nil {
	return nil, mapRepoErr(err)  // FK violation, UNIQUE violation, etc → gRPC status
}
```

**Паттерн:** `mapRepoErr(err)` трансформирует:
- `repo.ErrNotFound` → `codes.NotFound, "Network %s not found"`
- `repo.ErrAlreadyExists` → `codes.AlreadyExists, "..."`
- `repo.ErrFailedPrecondition` → `codes.FailedPrecondition, "..."`
- `repo.ErrInvalidArg` → `codes.InvalidArgument, "..."`
- Другие → `codes.Internal, "internal database error"` (без leak)

---

## Файл: network/update.go

### Что делает
UpdateNetworkUseCase обновляет mutable fields (name/description/labels) с UpdateMask discipline.

### Сигнатуры

```go
type UpdateInput struct {
	NetworkID  string
	Network    domain.Network  // несёт Name/Description/Labels
	UpdateMask []string        // поля из proto FieldMask.paths
}

func NewUpdateNetworkUseCase(r Repo, opsRepo operations.Repo) *UpdateNetworkUseCase

func (u *UpdateNetworkUseCase) Execute(ctx context.Context, in UpdateInput) (*operations.Operation, error)

func (u *UpdateNetworkUseCase) doUpdate(ctx context.Context, in UpdateInput) (*anypb.Any, error)
```

### Паттерны в update.go

#### 1. UpdateMask discipline
```go
func validateNetworkUpdate(in UpdateInput) error {
	known := map[string]struct{}{"name": {}, "description": {}, "labels": {}}
	if err := corevalidate.UpdateMask("update_mask", in.UpdateMask, known); err != nil {
		return err  // unknown field → InvalidArgument "unknown field: ..."
	}
	
	updates := in.UpdateMask
	if len(updates) == 0 {
		updates = []string{"name", "description", "labels"}  // full-object PATCH default
	}
	
	for _, f := range updates {
		switch f {
		case "name":
			if err := in.Network.Name.Validate(); err != nil {
				return err
			}
		// ... остальные
		}
	}
	return nil
}
```

**Паттерн UpdateMask:**
- **unknown field** → `InvalidArgument` (sync, в Execute).
- **hard-immutable field** (напр. folder_id) не in known-set → не пропустим даже в mask → `InvalidArgument`.
- **empty mask** → full-object PATCH: применяются ВСЕ mutable поля; immutable из тела **silent-ignore** (verbatim YC).
- **mask with known mutable field** → валидируем значение по тем же правилам.

#### 2. Get + Update в одной TX (race-free read-modify-write)
```go
func (u *UpdateNetworkUseCase) doUpdate(ctx context.Context, in UpdateInput) (*anypb.Any, error) {
	w, err := u.repo.Writer(ctx)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	defer w.Abort()

	// Get + мутация в одной writer-TX → race-free
	rec, err := w.Networks().Get(ctx, in.NetworkID)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	
	applyNetworkMask(&rec.Network, in)  // Применяем mask
	
	updated, err := w.Networks().Update(ctx, &rec.Network)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	
	if err := w.Outbox().Emit(ctx, "Network", updated.ID, "UPDATED", networkPayloadMap(updated)); err != nil {
		return nil, mapRepoErr(fmt.Errorf("%w: outbox emit: %v", repo.ErrInternal, err))
	}
	
	if err := w.Commit(); err != nil {
		return nil, mapRepoErr(err)
	}
	return marshalNetworkRecord(updated)
}
```

**Паттерн:** 
- Все three operations (Get, applyMask, Update) в одной Writer-TX.
- No intermediate Reads (вне TX) → no time-of-check-to-time-of-use race.
- Outbox emit в одной TX с Update → гарантирует уведомление в LISTEN'ерам.

#### 3. applyNetworkMask (mutable fields only)
```go
func applyNetworkMask(n *domain.Network, in UpdateInput) {
	if len(in.UpdateMask) == 0 {
		// Full PATCH: все mutable fields
		n.Name = in.Network.Name
		n.Description = in.Network.Description
		n.Labels = in.Network.Labels
		return
	}
	// Selective: только requested fields
	for _, field := range in.UpdateMask {
		switch field {
		case "name":
			n.Name = in.Network.Name
		case "description":
			n.Description = in.Network.Description
		case "labels":
			n.Labels = in.Network.Labels
		}
	}
}
```

**Паттерн:** Immutable fields (folder_id, etc.) никогда не применяются — даже если клиент прислал их в body без mask.

---

## Файл: network/delete.go

### Что делает
DeleteNetworkUseCase удаляет Network если она пуста (без Subnet, RouteTable, non-default SecurityGroup).

### Сигнатуры

```go
func NewDeleteNetworkUseCase(r Repo, subnetReader SubnetReader, routeTableRead RouteTableReader, sgRepo SecurityGroupRepo, opsRepo operations.Repo) *DeleteNetworkUseCase

func (u *DeleteNetworkUseCase) Execute(ctx context.Context, id string) (*operations.Operation, error)

func (u *DeleteNetworkUseCase) doDelete(ctx context.Context, id string) (*anypb.Any, error)

func (u *DeleteNetworkUseCase) checkNetworkEmpty(ctx context.Context, networkID string) error
```

### Паттерны в delete.go

#### 1. Sync precondition checks (child-class validation)
```go
func (u *DeleteNetworkUseCase) checkNetworkEmpty(ctx context.Context, networkID string) error {
	notEmpty := func() error {
		return status.Errorf(codes.FailedPrecondition, "Network %s is not empty", networkID)
	}
	
	// Проверяем subnets
	if u.subnetReader != nil {
		subs, _, err := u.subnetReader.List(ctx, SubnetFilter{NetworkID: networkID}, Pagination{})
		if err != nil {
			return mapRepoErr(err)
		}
		if len(subs) > 0 {
			return notEmpty()
		}
	}
	
	// Проверяем route tables
	if u.routeTableRead != nil {
		rts, _, err := u.routeTableRead.List(ctx, RouteTableFilter{NetworkID: networkID}, Pagination{})
		if err != nil {
			return mapRepoErr(err)
		}
		if len(rts) > 0 {
			return notEmpty()
		}
	}
	
	// Проверяем non-default SG
	if u.sgRepo != nil {
		sgs, _, err := u.sgRepo.List(ctx, SecurityGroupFilter{NetworkID: networkID}, Pagination{})
		if err != nil {
			return mapRepoErr(err)
		}
		for _, sg := range sgs {
			if !sg.DefaultForNetwork {
				return notEmpty()
			}
		}
	}
	return nil
}
```

**Паттерн:**
- Child-reader'ы optional (могут быть nil для unit-тестов).
- If nil → skip проверку (FK RESTRICT в worker'е всё равно ловит).
- Проверяем на empty перед Operation.Create (sync).
- Текст "Network %s is not empty" — verbatim YC.

#### 2. Async: Default-SG cleanup + Delete + Outbox
```go
func (u *DeleteNetworkUseCase) doDelete(ctx context.Context, id string) (*anypb.Any, error) {
	// Legacy cleanup: удалить default SG (отдельная TX через sgRepo; не CQRS ещё)
	if u.sgRepo != nil {
		rd, err := u.repo.Reader(ctx)
		if err == nil {
			n, gerr := rd.Networks().Get(ctx, id)
			_ = rd.Close()
			if gerr == nil && n.DefaultSecurityGroupID != "" {
				_ = u.sgRepo.Delete(ctx, n.DefaultSecurityGroupID)  // fire-and-forget
			}
		}
	}

	// Сам Delete + Outbox атомарны в CQRS-TX
	w, err := u.repo.Writer(ctx)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	defer w.Abort()

	if err := w.Networks().Delete(ctx, id); err != nil {
		return nil, mapRepoErr(err)
	}
	
	if err := w.Outbox().Emit(ctx, "Network", id, "DELETED", map[string]any{"id": id}); err != nil {
		return nil, mapRepoErr(fmt.Errorf("%w: outbox emit: %v", repo.ErrInternal, err))
	}
	
	if err := w.Commit(); err != nil {
		return nil, mapRepoErr(err)
	}
	return anypb.New(&emptypb.Empty{})  // Delete response = Empty (по proto)
}
```

**Паттерн:**
- Default-SG cleanup — legacy (через sgRepo, отдельная TX).
- Network Delete + Outbox.DELETED — одна CQRS-TX.
- Delete response = `&emptypb.Empty{}` завёрнутый в `*anypb.Any`.
- Metadata Operation.CreateDeleteNetworkMetadata уже есть (создана в Execute).

---

## Файл: network/get.go

### Что делает
GetNetworkUseCase — простой read по id.

### Сигнатуры

```go
func NewGetNetworkUseCase(r Repo) *GetNetworkUseCase

func (u *GetNetworkUseCase) Execute(ctx context.Context, id string) (*kachorepo.NetworkRecord, error)
```

### Паттерны в get.go

#### 1. Reader-TX для read
```go
func (u *GetNetworkUseCase) Execute(ctx context.Context, id string) (*kachorepo.NetworkRecord, error) {
	if err := corevalidate.ResourceID("network", ids.PrefixNetwork, id); err != nil {
		return nil, err  // unknown prefix → InvalidArgument
	}
	
	r, err := u.repo.Reader(ctx)  // Открыть Reader-TX
	if err != nil {
		return nil, mapRepoErr(err)
	}
	defer func() { _ = r.Close() }()
	
	n, err := r.Networks().Get(ctx, id)
	if err != nil {
		return nil, mapRepoErr(err)  // NotFound, или другая ошибка
	}
	return n, nil
}
```

**Паттерн:**
- Первый statement: ID-валидация `corevalidate.ResourceID("network", ids.PrefixNetwork, id)`.
- Открыть Reader-TX (в future — routing на реплику).
- `defer r.Close()` — закрыть TX.
- NotFound → `mapRepoErr(err)` → gRPC NotFound.

---

## Файл: network/list.go

### Что делает
List use-case'ы: ListNetworks, ListSubnets, ListSecurityGroups, ListRouteTables, ListOperations.

### Сигнатуры

```go
// ListNetworksUseCase
func NewListNetworksUseCase(r Repo) *ListNetworksUseCase
func (u *ListNetworksUseCase) Execute(ctx context.Context, f NetworkFilter, p Pagination) ([]*kachorepo.NetworkRecord, string, error)

// ListSubnetsUseCase
func NewListSubnetsUseCase(r Repo, subnetReader SubnetReader) *ListSubnetsUseCase
func (u *ListSubnetsUseCase) Execute(ctx context.Context, networkID string, p Pagination) ([]*kachorepo.SubnetRecord, string, error)

// ListOperationsUseCase
func NewListOperationsUseCase(opsRepo operations.Repo) *ListOperationsUseCase
func (u *ListOperationsUseCase) Execute(ctx context.Context, networkID string, p Pagination) ([]operations.Operation, string, error)
```

### Паттерны в list.go

#### 1. Folder-required validation
```go
func (u *ListNetworksUseCase) Execute(ctx context.Context, f NetworkFilter, p Pagination) ([]*kachorepo.NetworkRecord, string, error) {
	if f.FolderID == "" {
		return nil, "", status.Error(codes.InvalidArgument, "folder_id required")
	}
	r, err := u.repo.Reader(ctx)
	if err != nil {
		return nil, "", mapRepoErr(err)
	}
	defer func() { _ = r.Close() }()
	return r.Networks().List(ctx, f, p)
}
```

**Паттерн:** Project-owned lists требуют explicit owner-id (DB-колонка `folder_id` = id владельца-проекта, legacy-имя; публичный API — `projectId`). R10 #C1 — закрыто cross-project enumeration.

#### 2. Child-list с parent-existence-check
```go
func (u *ListSubnetsUseCase) Execute(ctx context.Context, networkID string, p Pagination) ([]*kachorepo.SubnetRecord, string, error) {
	if err := corevalidate.ResourceID("network", ids.PrefixNetwork, networkID); err != nil {
		return nil, "", err
	}
	
	rd, err := u.repo.Reader(ctx)
	if err != nil {
		return nil, "", mapRepoErr(err)
	}
	defer func() { _ = rd.Close() }()
	
	// Parent existence check
	if _, err := rd.Networks().Get(ctx, networkID); err != nil {
		return nil, "", mapRepoErr(err)  // NotFound parent → NotFound
	}
	
	if u.subnetReader == nil {
		return nil, "", nil
	}
	return u.subnetReader.List(ctx, SubnetFilter{NetworkID: networkID}, p)
}
```

**Паттерн:**
- ID-валидация.
- Parent-existence-check (NotFound parent → NotFound).
- Child-reader опционален (nil → nil результат).
- Всё в Reader-TX.

#### 3. ListOperations без existence-check
```go
// ListOperationsUseCase.Execute
func (u *ListOperationsUseCase) Execute(ctx context.Context, networkID string, p Pagination) ([]operations.Operation, string, error) {
	if err := corevalidate.ResourceID("network", ids.PrefixNetwork, networkID); err != nil {
		return nil, "", err
	}
	// НЕТ repo.Get(networkID) — операции доступны и после Delete (история)
	return u.opsRepo.List(ctx, operations.ListFilter{
		ResourceID: networkID,
		PageSize:   p.PageSize,
		PageToken:  p.PageToken,
	})
}
```

**Паттерн:** Операции в `operations`-таблице живут независимо (no FK). После Delete ресурса его операции остаются (история). ListOperations не требует existence-check.

---

## Файл: network/move.go

### Что делает
MoveNetworkUseCase перемещает Network в другой folder.

### Паттерны в move.go

#### 1. Sync checks: destination required, different, existence
```go
func (u *MoveNetworkUseCase) Execute(ctx context.Context, id, destFolderID string) (*operations.Operation, error) {
	if err := corevalidate.ResourceID("network", ids.PrefixNetwork, id); err != nil {
		return nil, err
	}
	if id == "" {
		return nil, status.Error(codes.InvalidArgument, "network_id required")
	}
	if destFolderID == "" {
		return nil, invalidArg("destination_folder_id", "destination_folder_id is required")
	}
	
	rd, err := u.repo.Reader(ctx)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	cur, err := rd.Networks().Get(ctx, id)
	_ = rd.Close()
	if err != nil {
		return nil, mapRepoErr(err)
	}
	
	// Проверяем: не в тот же project (DB-колонка folder_id = id владельца-проекта, legacy-имя)
	if err := checkMoveDestination(ctx, u.projectClient, cur.ProjectID, destProjectID); err != nil {
		return nil, err  // InvalidArgument: "Destination folder is the same as the source"
	}
	// ...
}

func checkMoveDestination(_ context.Context, _ ProjectClient, currentProjectID, destProjectID string) error {
	if currentProjectID == destProjectID {
		return invalidArg("destination_folder_id", "Destination folder is the same as the source")
	}
	return nil
}
```

#### 2. Async: двойная project-existence-check
```go
func (u *MoveNetworkUseCase) doMove(ctx context.Context, id, destProjectID string) (*anypb.Any, error) {
	// Повторная project-existence-check (backstop) — peer = kacho-iam (KAC-106)
	exists, err := u.projectClient.Exists(ctx, destProjectID)
	if err != nil {
		return nil, status.Errorf(codes.Unavailable, "folder check: %v", err)
	}
	if !exists {
		return nil, status.Errorf(codes.NotFound, "Folder with id %s not found", destFolderID)
	}

	w, err := u.repo.Writer(ctx)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	defer w.Abort()

	updated, err := w.Networks().SetFolderID(ctx, id, destFolderID)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	
	if err := w.Outbox().Emit(ctx, "Network", updated.ID, "UPDATED", networkPayloadMap(updated)); err != nil {
		return nil, mapRepoErr(fmt.Errorf("%w: outbox emit: %v", repo.ErrInternal, err))
	}
	
	if err := w.Commit(); err != nil {
		return nil, mapRepoErr(err)
	}
	return marshalNetworkRecord(updated)
}
```

**Паттерн:** 
- Sync проверка: destination требуется, не == source, exists (минимальная).
- Async: повторная folder-existence-check (race-safe backstop), SetFolderID, outbox emit.

---

## Файл: subnet/handler.go

### Что делает
SubnetServiceServer реализация. Структура и паттерны аналогичны Network.

### Отличия от Network/handler.go

```go
func NewHandler(
	create *CreateSubnetUseCase,
	update *UpdateSubnetUseCase,
	deleteUC *DeleteSubnetUseCase,
	move *MoveSubnetUseCase,
	get *GetSubnetUseCase,
	list *ListSubnetsUseCase,
	addCidrBlocks *AddCidrBlocksUseCase,
	removeCidrBlocks *RemoveCidrBlocksUseCase,
	relocate *RelocateUseCase,
	listUsedAddresses *ListUsedAddressesUseCase,
	listOperations *ListOperationsUseCase,
) *Handler
```

**Дополнительные use-case'ы:**
- `AddCidrBlocksUseCase` — добавить CIDR-блоки.
- `RemoveCidrBlocksUseCase` — удалить CIDR-блоки.
- `RelocateUseCase` — переместить в другую зону (всегда FAILED_PRECONDITION).
- `ListUsedAddressesUseCase` — список используемых IP в подсети.

---

## Файл: subnet/create.go

### Паттерны (отличия от Network)

#### 1. ZoneRegistry валидация
```go
// ZoneId: required + existence в таблице `zones` (без hardcoded whitelist)
if err := validateZoneID(ctx, u.zoneReg, "zone_id", s.ZoneID); err != nil {
	return nil, err
}
```

**Паттерн:** ZoneRegistry.Get(ctx, zoneID) → либо *domain.Zone, либо error (NotFound → InvalidArgument "invalid zone_id").

#### 2. CIDR валидация
```go
// v4_cidr_blocks опциональны (не required)
for i, c := range s.V4CidrBlocks {
	if err := validateSubnetV4CIDR(fmt.Sprintf("v4_cidr_blocks[%d]", i), c); err != nil {
		return nil, err  // host-bits, format, etc
	}
}

// v6_cidr_blocks опциональны
for i, c := range s.V6CidrBlocks {
	if err := validateSubnetV6CIDR(fmt.Sprintf("v6_cidr_blocks[%d]", i), c); err != nil {
		return nil, err
	}
}
```

**Паттерн:** CIDR валидируется в use-case (host-bits=0, /16..28 для v4, etc).

#### 3. Sync CIDR overlap check
```go
func (u *CreateSubnetUseCase) checkSubnetCIDROverlap(ctx context.Context, rd Reader, folderID, networkID string, v4 []string) error {
	if len(v4) == 0 {
		return nil
	}
	newPrefixes := make([]netipPrefix, 0, len(v4))
	for _, c := range v4 {
		pr, err := parseNetipPrefix(c)
		if err != nil {
			return invalidArg("v4_cidr_blocks", "must be valid CIDR")
		}
		newPrefixes = append(newPrefixes, pr)
	}
	
	existing, _, err := rd.Subnets().List(ctx, SubnetFilter{FolderID: folderID, NetworkID: networkID}, Pagination{})
	if err != nil {
		return mapRepoErr(err)
	}
	
	for _, sub := range existing {
		for _, raw := range sub.V4CidrBlocks {
			pr, perr := parseNetipPrefix(raw)
			if perr != nil {
				continue
			}
			for _, np := range newPrefixes {
				if prefixesOverlap(pr, np) {
					return status.Errorf(codes.FailedPrecondition, "Subnet CIDRs can not overlap")
				}
			}
		}
	}
	return nil
}
```

**Паттерн:**
- Sync overlap-check через Reader.Subnets().List по folder+network.
- DB-level EXCLUDE constraint (subnets_no_overlap_v4) — atomic backstop для primary CIDR.
- Sync-check покрывает и secondary CIDR (где DB-level не срабатывает).

#### 4. Parent network existence check
```go
rd, err := u.repo.Reader(ctx)
if err != nil {
	return nil, mapRepoErr(err)
}
if _, gerr := rd.Networks().Get(ctx, s.NetworkID); gerr != nil {
	_ = rd.Close()
	if errors.Is(gerr, repo.ErrNotFound) {
		return nil, status.Errorf(codes.NotFound, "Network %s not found", s.NetworkID)
	}
	return nil, mapRepoErr(gerr)
}
```

**Паттерн:** Перед Operation — проверить Network существует (синхронно).

#### 5. Async doCreate
```go
func (u *CreateSubnetUseCase) doCreate(ctx context.Context, subID string, s domain.Subnet) (*anypb.Any, error) {
	exists, err := u.projectClient.Exists(ctx, s.ProjectID)  // peer = kacho-iam (KAC-106); s.ProjectID в DB-колонке folder_id
	if err != nil {
		return nil, status.Errorf(codes.Unavailable, "folder check: %v", err)
	}
	if !exists {
		return nil, status.Errorf(codes.NotFound, "Folder with id %s not found", s.FolderID)
	}

	s.ID = subID

	w, err := u.repo.Writer(ctx)
	if err != nil {
		return nil, mapRepoErr(err)
	}
	defer w.Abort()

	// Parent network existence — повторная проверка в writer-TX (atomic backstop)
	if _, gerr := w.Networks().Get(ctx, s.NetworkID); gerr != nil {
		return nil, status.Errorf(codes.NotFound, "Network %s not found", s.NetworkID)
	}

	created, err := w.Subnets().Insert(ctx, &s)
	if err != nil {
		return nil, mapRepoErr(err)  // EXCLUDE constraint violation → FailedPrecondition
	}
	
	if err := w.Outbox().Emit(ctx, "Subnet", created.ID, "CREATED", subnetPayloadMap(created)); err != nil {
		return nil, mapRepoErr(fmt.Errorf("%w: outbox emit: %v", repo.ErrInternal, err))
	}
	
	if err := w.Commit(); err != nil {
		return nil, mapRepoErr(err)
	}
	return marshalSubnetRecord(created)
}
```

**Паттерн:**
- Folder-existence-check (async backstop).
- Parent-network-existence-check (atomic backstop).
- Insert в writer-TX.
- Outbox emit в той же TX.
- EXCLUDE constraint проверяет primary CIDR.

---

## Файл: subnet/update.go

### Паттерны (отличия от Network)

#### 1. Hard-immutable check в Execute
```go
for _, field := range in.UpdateMask {
	switch field {
	case "network_id", "zone_id":
		return nil, invalidArg(field, field+" is immutable after Subnet.Create")
	}
}
```

**Паттерн:** Попытка explicitly указать hard-immutable field в mask → sync InvalidArgument.

#### 2. Soft-immutable silence (v4_cidr_blocks)
```go
// v4_cidr_blocks / v6_cidr_blocks — verbatim YC НЕ отвергает их в mask (принимает 200)
// но мы в репо Update НЕ перезаписываем CIDR-колонки → no-op (документировано).

known := map[string]struct{}{
	"name": {}, "description": {}, "labels": {},
	"route_table_id": {}, "dhcp_options": {},
	"v4_cidr_blocks": {}, "v6_cidr_blocks": {}, "network_id": {}, "zone_id": {},
}
if err := corevalidate.UpdateMask("update_mask", in.UpdateMask, known); err != nil {
	return err
}
```

**Паттерн:**
- v4/v6_cidr_blocks в known-set (не unknown).
- network_id/zone_id тоже в known-set (для hard-immutable-check выше).
- Но в applySubnetMask — они НЕ применяются никогда.

#### 3. applySubnetMask
```go
func applySubnetMask(sub *domain.Subnet, in UpdateInput) {
	if len(in.UpdateMask) == 0 {
		// Полный update — только mutable fields
		sub.Name = in.Subnet.Name
		sub.Description = in.Subnet.Description
		sub.Labels = in.Subnet.Labels
		sub.RouteTableID = in.Subnet.RouteTableID
		sub.DhcpOptions = in.Subnet.DhcpOptions
		return
	}
	// Selective
	for _, field := range in.UpdateMask {
		switch field {
		case "name":
			sub.Name = in.Subnet.Name
		case "description":
			sub.Description = in.Subnet.Description
		case "labels":
			sub.Labels = in.Subnet.Labels
		case "route_table_id":
			sub.RouteTableID = in.Subnet.RouteTableID
		case "dhcp_options":
			sub.DhcpOptions = in.Subnet.DhcpOptions
		}
		// НИКОГДА не применяем: network_id, zone_id, v4_cidr_blocks, v6_cidr_blocks
	}
}
```

---

## Файл: subnet/delete.go

### Паттерны

#### 1. Двойная precondition: Address + NetworkInterface
```go
func (u *DeleteSubnetUseCase) checkNetworkEmpty(ctx context.Context, id string) error {
	// Verbatim YC: Subnet с internal Address'ами удалить нельзя
	addrs, _, aerr := rd.Subnets().AddressesBySubnet(ctx, id, Pagination{})
	if aerr != nil {
		return mapRepoErr(aerr)
	}
	if len(addrs) > 0 {
		return status.Error(codes.FailedPrecondition, "Subnet has allocated internal addresses")
	}
	
	// KAC-33: NIC→Subnet FK = ON DELETE RESTRICT
	if u.nicRepo != nil {
		nics, nerr := u.nicRepo.ListBySubnet(ctx, id)
		if nerr != nil {
			return mapRepoErr(nerr)
		}
		if len(nics) > 0 {
			nicIDs := make([]string, 0, len(nics))
			for _, n := range nics {
				nicIDs = append(nicIDs, n.ID)
			}
			return status.Errorf(codes.FailedPrecondition,
				"subnet %s has %d network interface(s) (%s); delete them first", id, len(nics), strings.Join(nicIDs, ", "))
		}
	}
	return nil
}
```

**Паттерн:**
- Сначала check Address'ы.
- Потом check NetworkInterface'ы.
- nicRepo опционален (nil → проверка пропускается; FK RESTRICT всё равно ловит).
- Сообщение об ошибке содержит список NIC-id.

#### 2. Hard-delete (не soft)
```go
if err := w.Subnets().Delete(ctx, id); err != nil {
	return nil, mapRepoErr(err)  // FK RESTRICT → FailedPrecondition если есть дети
}

if err := w.Outbox().Emit(ctx, "Subnet", id, "DELETED", map[string]any{"id": id}); err != nil {
	return nil, mapRepoErr(fmt.Errorf("%w: outbox emit: %v", repo.ErrInternal, err))
}

if err := w.Commit(); err != nil {
	return nil, mapRepoErr(err)
}
return anypb.New(&emptypb.Empty{})
```

**Паттерн:** Hard-delete — DELETE FROM. Никаких deletion_timestamp, finalizers, tombstones.

---

## Файл: subnet/add_cidr_blocks.go

### Паттерны

#### 1. Inline operations в Operation worker'е
```go
operations.Run(ctx, u.opsRepo, op.ID, func(ctx context.Context) (*anypb.Any, error) {
	w, werr := u.repo.Writer(ctx)
	if werr != nil {
		return nil, mapRepoErr(werr)
	}
	defer w.Abort()

	sub, gerr := w.Subnets().Get(ctx, id)
	if gerr != nil {
		return nil, mapRepoErr(gerr)
	}
	
	mergedV4 := append([]string{}, sub.V4CidrBlocks...)
	mergedV4 = append(mergedV4, v4...)
	
	if err := checkCIDRDisjoint("v4_cidr_blocks", mergedV4); err != nil {
		return nil, err
	}
	
	updated, uerr := w.Subnets().SetCidrBlocks(ctx, id, mergedV4, mergedV6)
	if uerr != nil {
		return nil, mapRepoErr(uerr)
	}
	
	if err := w.Outbox().Emit(ctx, "Subnet", updated.ID, "UPDATED", subnetPayloadMap(updated)); err != nil {
		return nil, mapRepoErr(fmt.Errorf("%w: outbox emit: %v", repo.ErrInternal, err))
	}
	
	if err := w.Commit(); err != nil {
		return nil, mapRepoErr(err)
	}
	return marshalSubnetRecord(updated)
})
```

**Паттерн:** Весь code (Get, merge, SetCidrBlocks, outbox) ВНУТРИ Operation worker'а, в одной TX. Не отдельная async-функция.

#### 2. checkCIDRDisjoint (не overlap)
```go
func checkCIDRDisjoint(field string, cidrs []string) error {
	if len(cidrs) == 0 {
		return nil
	}
	prefixes := make([]netipPrefix, 0, len(cidrs))
	for i, c := range cidrs {
		pr, err := parseNetipPrefix(c)
		if err != nil {
			return invalidArg(field, fmt.Sprintf("invalid CIDR %q", c))
		}
		prefixes = append(prefixes, pr)
	}
	for i := 0; i < len(prefixes); i++ {
		for j := i + 1; j < len(prefixes); j++ {
			if prefixesOverlap(prefixes[i], prefixes[j]) {
				return status.Errorf(codes.InvalidArgument, "%s can not overlap each other", field)
			}
		}
	}
	return nil
}
```

**Паттерн:**
- Проверяет: CIDR'ы внутри переданного списка не пересекаются между собой (инфра-проверка перед SetCidrBlocks).
- Возвращает InvalidArgument (не FailedPrecondition).

---

## Файл: network/iface.go, subnet/iface.go

### Паттерны интерфейсов

```go
// network/iface.go
type (
	Repo               = kacho.Repository          // CQRS Repository
	Reader             = kacho.RepositoryReader    // CQRS Reader TX
	Writer             = kacho.RepositoryWriter    // CQRS Writer TX
)

// Port-интерфейсы для use-case'ов
type SubnetReader interface {
	List(ctx context.Context, f SubnetFilter, p Pagination) ([]*kacho.SubnetRecord, string, error)
}

type SecurityGroupRepo interface {
	List(ctx context.Context, f SecurityGroupFilter, p Pagination) ([]*kacho.SecurityGroupRecord, string, error)
	Insert(ctx context.Context, sg *domain.SecurityGroup) (*kacho.SecurityGroupRecord, error)
	Delete(ctx context.Context, id string) error
}

type ProjectClient interface {  // renamed from FolderClient в KAC-106; peer = kacho-iam
	Exists(ctx context.Context, folderID string) (bool, error)  // folderID = projectID (legacy param-имя)
	GetCloudIDFromProject(ctx context.Context, projectID string) (string, error)
}
```

**Паттерн:**
- Type-alias (не type wrap) для CQRS Repository.
- Port-интерфейсы (narrow) для use-case-зависимостей.
- Опциональные интерфейсы (могут быть nil) — graceful degradation в unit-тестах.

---

## Helpers-функции (общие для network и subnet)

```go
// Payloads для outbox.Emit
func networkPayloadMap(rec *kachorepo.NetworkRecord) map[string]any {
	return map[string]any{
		"id":          rec.ID,
		"folder_id":   rec.FolderID,
		"name":        string(rec.Name),
		// ... остальные поля
	}
}

// marshalNetworkRecord завёрнуть в *anypb.Any
func marshalNetworkRecord(rec *kachorepo.NetworkRecord) (*anypb.Any, error) {
	pb, err := networkToPb(rec)
	if err != nil {
		return nil, err
	}
	return anypb.New(pb)
}

// mapRepoErr — трансляция repo-sentinel в gRPC status
func mapRepoErr(err error) error {
	if errors.Is(err, repo.ErrNotFound) {
		return status.Error(codes.NotFound, "...")
	}
	if errors.Is(err, repo.ErrAlreadyExists) {
		return status.Error(codes.AlreadyExists, "...")
	}
	// ...
	return status.Error(codes.Internal, "internal database error")
}

// invalidArg — shorthand для status.Errorf(codes.InvalidArgument)
func invalidArg(field, msg string) error {
	return status.Errorf(codes.InvalidArgument, "Invalid field %q: %s", field, msg)
}
```

---

## Итоговая архитектурная картина

```
┌─────────────────────────────────────────────────────────────────┐
│ gRPC Transport (handler.go)                                      │
│ └─ Proto-parsing, folder-ownership AuthZ, DTO transfer           │
└─────────────────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────────────────┐
│ Use-Case Pattern (create.go, update.go, delete.go, move.go)     │
│ ├─ SYNC: ID-валидация, format-валидация, uniqueness/overlap    │
│ │        checks через Reader-TX; Operation.New + Create         │
│ └─ ASYNC: operations.Run(ctx, opsRepo, opID, worker)            │
│           Worker открывает Writer-TX:                            │
│           ├─ Folder/Network-existence-check (backstop)          │
│           ├─ DML (Insert/Update/Delete/SetFolderID)             │
│           ├─ Outbox.Emit (CREATED/UPDATED/DELETED)              │
│           └─ w.Commit() (atomicity DML + outbox)                │
└─────────────────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────────────────┐
│ CQRS Repository (internal/repo/kacho)                            │
│ ├─ Reader: List, Get                                             │
│ ├─ Writer: Insert, Update, Delete, SetFolderID, SetCidrBlocks   │
│ ├─ Outbox: Emit (map[string]any)                                │
│ └─ TX: w.Commit() / w.Abort() / r.Close()                       │
└─────────────────────────────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────────────────────────────┐
│ Postgres (internal/migrations/0001_initial.sql)                  │
│ ├─ Tables: networks, subnets, addresses, route_tables, ...      │
│ ├─ Constraints: FK (ON DELETE RESTRICT/SET NULL),               │
│ │              UNIQUE partial, CHECK, EXCLUDE gist               │
│ ├─ Triggers: vpc_outbox_notify_trg (pg_notify), auto-route-assoc │
│ └─ Outbox: vpc_outbox table + LISTEN/NOTIFY                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Naming Conventions

| Тип | Пример | Замечание |
|-----|--------|----------|
| Use-Case struct | `CreateNetworkUseCase`, `UpdateSubnetUseCase` | Suffix: UseCase |
| Use-Case method | `Execute`, `doCreate` | Execute = public; do* = private async |
| Input struct | `UpdateInput` | Optional; только если параметры не в domain-модели |
| Handler struct | `Handler` | Реализует вещание ServiceServer |
| Handler method | `Get`, `Create`, `List` | Имена RPC методов |
| Filter struct | `NetworkFilter`, `SubnetFilter` | Переиспользуемые из repo |
| Pagination | `Pagination` | Переиспользуемая из repo |
| Domain model | `domain.Network`, `domain.Subnet` | Каноническая бизнес-логика |
| Repository record | `kachorepo.NetworkRecord`, `kachorepo.SubnetRecord` | Результат repo.Get, repo.Insert |
| Proto | `vpcv1.Network`, `operationpb.Operation` | Generated из .proto |
| Port interface | `ProjectClient` (was `FolderClient`, KAC-106), `ZoneRegistry`, `SubnetReader` | Narrow; опциональны |

---

## Ключевые инсайты

1. **Operation async** — клиент получает Operation id сразу; worker в фоне; уведомление через LISTEN/NOTIFY.
2. **CQRS Repository** — Reader и Writer открыты явно; atomicity через defer+Commit.
3. **Outbox emit в TX** — гарантирует notification при успехе.
4. **Sync + Async backstops** — sync-check на request-path (fast-fail), async folder/network-check в worker (race-safe).
5. **UpdateMask discipline** — unknown → InvalidArgument, hard-immutable → InvalidArgument, soft-immutable → silent-ignore.
6. **Error mapping** — repo-sentinel → gRPC status (NotFound/AlreadyExists/FailedPrecondition/InvalidArgument/Internal).
7. **Child preconditions** — перед Delete Subnet: check Address'ы + NetworkInterface'ы.
8. **ID validation first** — `corevalidate.ResourceID` первый statement в каждом id-берущем RPC.

