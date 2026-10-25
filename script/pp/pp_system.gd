extends RefCounted
class_name PPSystem

## pp（实力值）计算。单场 pp 都按 "基础值 × (有效数 / 总数)²"，
## 有效数 = 做对数量 − 做错数量；总 pp 取最高的 100 场，按 0.95 的权重递减求和（osu 的算法）。

const ECP_TOTAL_PAIRS := 30
const ECP_BASE := {
	Word.Level.PRIMARY: 50.0,
	Word.Level.INTERMEDIATE: 100.0,
	Word.Level.ADVANCED: 300.0,
}
## 快问快答 60 秒一局，60 题 = 200pp；超过 60 题继续按平方增长
const QQNA_BASE := 200.0
const QQNA_REFERENCE := 60
const QSPE_BASE := 150.0
const QSPE_REFERENCE := 20

const TOP_N := 100
const WEIGHT_DECAY := 0.95


## 二次曲线。capped 为 false 时超过参考数量可以继续涨（快问快答用）。
static func curve(base: float, effective: int, total: int, capped: bool = true) -> float:
	if total <= 0:
		return 0.0
	var ratio := maxf(float(effective), 0.0) / float(total)
	if capped:
		ratio = minf(ratio, 1.0)
	return snappedf(base * ratio * ratio, 0.01)


static func ecp_pp(level: int, correct: int, wrong: int) -> float:
	return curve(ECP_BASE.get(level, ECP_BASE[Word.Level.PRIMARY]), maxi(correct - wrong, 0), ECP_TOTAL_PAIRS)


static func qqna_pp(correct: int, wrong: int) -> float:
	return curve(QQNA_BASE, maxi(correct - wrong, 0), QQNA_REFERENCE, false)


static func qspe_pp(correct: int, wrong: int) -> float:
	return curve(QSPE_BASE, maxi(correct - wrong, 0), QSPE_REFERENCE)


## 从所有游玩记录算总 pp
static func total_pp(plays: Array) -> float:
	var values: Array[float] = []
	for play in plays:
		var record := play as PlayRecord
		if record == null:
			continue
		values.append(maxf(record.pp, 0.0))
	values.sort()
	values.reverse()
	var total := 0.0
	for i in mini(values.size(), TOP_N):
		total += values[i] * pow(WEIGHT_DECAY, i)
	return snappedf(total, 0.01)


## 第 index 场（从 0 开始）的权重，用于界面展示
static func weight_at(index: int) -> float:
	return pow(WEIGHT_DECAY, index)


static func ecp_base(level: int) -> float:
	return ECP_BASE.get(level, Word.Level.PRIMARY)
