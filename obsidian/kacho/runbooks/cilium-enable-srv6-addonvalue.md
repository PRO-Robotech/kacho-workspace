---
title: "Runbook: включить SRv6 в Cilium через AddonValue (infra-кластер)"
category: runbook
tags:
  - runbook
  - kacho-vpc
  - experimental
  - srv6
  - cilium
---

# Runbook: включить SRv6 в Cilium через AddonValue

Кластер `fe3455-infra` (KUBECONFIG), Cilium 1.19.4 (ns `beget-cilium`), управляется
addon-контроллером (`addons.in-cloud.io`). Ядро 6.8 (SRv6-capable). Верифицировано 2026-06-13.

> [!important] Правило изменений
> Менять **только через AddonValue**. Всё остальное — только **рестарт пода** и
> **триггер реконсила** (`kubectl annotate addon … reconcile=<ts>`, argocd
> `refresh=hard`). НИКАКИХ `kubectl patch/edit` на rendered-ресурсах — argocd
> selfHeal их откатит, а ручной правкой можно уронить сеть (см. «Инцидент»).

## AddonValue (источник истины)

`AddonValue` cluster-scoped, лейблы `addons.in-cloud.io/addon: cilium` +
`addons.in-cloud.io/values: custom` (Addon.spec.valuesSelectors priority 95).
`spec.values` = helm-values (под ключом `cilium:`, т.к. cilium — сабчарт).

```yaml
apiVersion: addons.in-cloud.io/v1alpha1
kind: AddonValue
metadata:
  name: cilium-custom
  labels: {addons.in-cloud.io/addon: cilium, addons.in-cloud.io/values: custom}
spec:
  values: |
    cilium:
      ipv6:
        enabled: true                      # SRv6 ТРЕБУЕТ IPv6 (иначе agent fatal)
      ipam:
        operator:
          clusterPoolIPv6PodCIDRList: ["fd00:cafe::/48"]
          clusterPoolIPv6MaskSize: 64
      extraConfig:
        enable-srv6: "true"                # чарт НЕ шаблонит srv6.enabled → только extraConfig
```

## Гочи (выстраданные)

1. **`srv6.enabled` чарт игнорит** (нет srv6-шаблона в beget-чарте 1.19.4) → флаг
   `enable-srv6` задаётся через `cilium.extraConfig` (прямая инъекция в configmap).
2. **`enable-ipv6` через extraConfig НЕ работает** — чарт явно шаблонит этот ключ и
   перебивает extraConfig. Включать через chart-value `cilium.ipv6.enabled: true`.
3. **SRv6 требует IPv6**: без него agent `level=fatal "SRv6 requires IPv6"` → crashloop.
4. **IPv6 требует v6 pod-CIDR**: иначе agent `required IPv6 PodCIDR not available`,
   operator должен его аллоцировать. Дефолт чарта `fd00::/104`; задать свой через
   `ipam.operator.clusterPoolIPv6PodCIDRList` (deep-merge с immutable v4 переживает).
5. **Поды не пересобираются на смену configmap** (предупреждение Cilium) — после
   реконсила `kubectl -n beget-cilium rollout restart ds/cilium deploy/cilium-operator`
   (или `delete pod`). Operator рестартить — чтобы выдал узлу v6 PodCIDR.

## Порядок применения

1. `kubectl apply` AddonValue `cilium-custom` (единственная ручная сущность — это CR addon-а, не rendered-ресурс).
2. `kubectl annotate addon cilium addons.in-cloud.io/reconcile=$(date +%s) --overwrite` → operator пере-резолвит HELM_VALUES.
3. `kubectl -n beget-argocd annotate application cilium argocd.argoproj.io/refresh=hard --overwrite` → argocd рендерит+синкает configmap.
4. `kubectl -n beget-cilium rollout restart ds/cilium deploy/cilium-operator`.
5. Verify: `cilium-dbg status | grep SRv6` → `Enabled`; `ls /sys/fs/bpf/tc/globals | grep srv6` → 5 map'ов.

## Инцидент 2026-06-13 (урок)

Ручной `kubectl patch cm cilium-config` (enable-ipv6) + crashloop единственного
agent'а на узле → сеть деградировала → coredns/argocd DNS i/o timeout → argocd не мог
рендерить (chicken-and-egg). Восстановление: rollout restart coredns + argocd-repo-server,
выравнивание desired через AddonValue. **Вывод: только AddonValue + restart/reconcile.**

## Связь с CIL-треком

SRv6-датаплейн поднят → `cilium_srv6_vrf_v4/v6` существуют → разблокирована
**CIL1b** (srv6adapter: запись `compiler.VRFEntry` в VRF-map) и datapath-верификация.
См. [[../packages/kacho-vpc-cilium-compiler]], [[../edges/vpc-operator-to-cilium-realization]].

#runbook #kacho-vpc #experimental #srv6 #cilium
