---
name: python-prime-calculator
version: 1.0.0
description: |
  编写并执行Python代码计算指定范围内的质数，返回质数列表和总数
triggers:
  - "计算质数"
  - "求质数"
  - "质数个数"
  - "找素数"
  - "python质数"
mutating: false
---

# python-prime-calculator

## Contract
保证能正确识别质数（只能被1和自身整除的自然数），返回指定范围内的完整质数列表和准确的计数

## Phases
1. 编写is_prime()函数，使用优化的质数判断算法（检查2、偶数、然后从3到√n的奇数）
2. 使用列表推导式遍历目标范围，过滤出所有质数
3. 执行代码并打印质数列表和总数

## 注意
- 质数从2开始，1不是质数
- 优化点：n<2直接返回False，n==2单独处理，偶数直接排除，只检查到√n
- 用range(3, int(n**0.5) + 1, 2)遍历奇数可大幅提升效率
- 始终立即执行代码并验证结果，不要只输出代码
