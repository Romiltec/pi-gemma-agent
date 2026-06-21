// Reference implementation — passes every rung. Used to validate the judge.
module.exports = {
  add: (a, b) => a + b,
  isEven: (n) => n % 2 === 0,
  reverse: (s) => s.split('').reverse().join(''),
  clamp: (x, lo, hi) => Math.max(lo, Math.min(hi, x)),
  fib: (n) => { let a = 0, b = 1; for (let i = 0; i < n; i++) { [a, b] = [b, a + b]; } return a; },
  fizzbuzz: (n) => { const o = []; for (let i = 1; i <= n; i++) o.push(i % 15 === 0 ? 'FizzBuzz' : i % 3 === 0 ? 'Fizz' : i % 5 === 0 ? 'Buzz' : i); return o; },
  unique: (a) => [...new Set(a)],
};
