// A tiny CommonJS utility module. Each ladder step adds one pure function.
module.exports = {
  add: (a, b) => a + b,
  isEven: (n) => n % 2 === 0,
  reverse: (str) => str.split('').reverse().join(''),
  clamp: (x, lo, hi) => Math.min(Math.max(x, lo), hi),
  fib: (n) => {
    if (n <= 0) return 0;
    if (n === 1) return 1;
    let a = 0, b = 1;
    for (let i = 2; i <= n; i++) {
      [a, b] = [b, a + b];
    }
    return b;
  },
  fizzbuzz: (n) => {
    const result = [];
    for (let i = 1; i <= n; i++) {
      if (i % 3 === 0 && i % 5 === 0) {
        result.push('FizzBuzz');
      } else if (i % 3 === 0) {
        result.push('Fizz');
      } else if (i % 5 === 0) {
        result.push('Buzz');
      } else {
        result.push(i);
      }
    }
    return result;
  },
  unique: (arr) => [...new Set(arr)],
};
