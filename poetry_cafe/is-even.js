/*!
 * is-even <https://github.com/jonschlinkert/is-even>
 *
 * Copyright (c) 2015-present, Jon Schlinkert.
 * Released under the MIT License.
 */

'use strict';

import isNumber from './is-number.js';

export default function isEven(i) {
  if (!isNumber(i)) {
    throw new TypeError('is-even expects a number.');
  }
  if (Number(i) % 2 === 0) {
    return true;
  }
  return false;
};
