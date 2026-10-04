// Package sim 实现客户端与后端共享的确定性模拟原语。
//
// 一致性约束：本包的随机数与时间映射必须与客户端 GDScript 实现逐位一致，
// 规格与测试向量见 shared/consistency/。
package sim
