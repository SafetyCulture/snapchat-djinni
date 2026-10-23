/**
  * Copyright 2021 Snap, Inc.
  *
  * Licensed under the Apache License, Version 2.0 (the "License");
  * you may not use this file except in compliance with the License.
  * You may obtain a copy of the License at
  *
  *    http://www.apache.org/licenses/LICENSE-2.0
  *
  * Unless required by applicable law or agreed to in writing, software
  * distributed under the License is distributed on an "AS IS" BASIS,
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  * See the License for the specific language governing permissions and
  * limitations under the License.
  */

package com.snapchat.djinni;

/**
 * A C++ exception that the JNI code translated to Java: an exception of the C++ method, an exception that is not
 * derived from std::exception, or the error of a C++ future. The message is the text of the C++ exception.
 * It is a RuntimeException, so each catch block for RuntimeException still works.
 */
public class DjinniCppException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    public DjinniCppException(String message) {
        super(message);
    }
}
