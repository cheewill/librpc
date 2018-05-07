#
# Copyright 2017 Two Pore Guys, Inc.
# All rights reserved
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted providing that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES LOSS OF USE, DATA, OR PROFITS OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

class ObjectType(enum.IntEnum):
    """
    Enumeration of possible object types.
    """
    NIL = RPC_TYPE_NULL
    BOOL = RPC_TYPE_BOOL
    UINT64 = RPC_TYPE_UINT64
    INT64 = RPC_TYPE_INT64
    DOUBLE = RPC_TYPE_DOUBLE
    DATE = RPC_TYPE_DATE
    STRING = RPC_TYPE_STRING
    BINARY = RPC_TYPE_BINARY
    FD = RPC_TYPE_FD
    ERROR = RPC_TYPE_ERROR
    DICTIONARY = RPC_TYPE_DICTIONARY
    ARRAY = RPC_TYPE_ARRAY


class LibException(Exception):
    def __init__(self, code=None, message=None, extra=None, stacktrace=None, obj=None):
        if obj:
            self.code = obj['code']
            self.message = obj['message']
            self.extra = obj.get('extra')
            return

        self.code = code
        self.message = message
        self.extra = extra
        self.obj = obj

        tb = sys.exc_info()[2]
        if stacktrace is None and tb:
            stacktrace = tb

        if isinstance(stacktrace, types.TracebackType):
            def serialize_traceback(tb):
                iter_tb = tb if isinstance(tb, (list, tuple)) else traceback.extract_tb(tb)
                return [
                    {
                        'filename': f[0],
                        'lineno': f[1],
                        'method': f[2],
                        'code': f[3]
                    }
                    for f in iter_tb
                ]

            stacktrace = serialize_traceback(stacktrace)

        self.stacktrace = stacktrace

    def __str__(self):
        return "[{0}] {1}".format(os.strerror(self.code), self.message)


class RpcException(LibException):
    pass


cdef class Object(object):
    """
    A boxed librpc object.
    """
    def __init__(self, value, force_type=None, typei=None):
        """
        Create a new boxed object.

        :param value: Value to box
        :param force_type: Force a non-default type (eg. unsigned int)
        :param typei: Type instance to annotate the object
        """

        if value is None or force_type == ObjectType.NIL:
            self.obj = rpc_null_create()

        elif isinstance(value, bool) or force_type == ObjectType.BOOL:
            self.obj = rpc_bool_create(value)

        elif isinstance(value, int) and force_type == ObjectType.UINT64:
            self.obj = rpc_uint64_create(value)

        elif isinstance(value, int) and force_type == ObjectType.FD:
            self.obj = rpc_fd_create(value)

        elif isinstance(value, int) or force_type == ObjectType.INT64:
            self.obj = rpc_int64_create(value)

        elif isinstance(value, str) or force_type == ObjectType.STRING:
            bstr = value.encode('utf-8')
            self.obj = rpc_string_create(bstr)

        elif isinstance(value, float) or force_type == ObjectType.DOUBLE:
            self.obj = rpc_double_create(value)

        elif isinstance(value, datetime.datetime) or force_type == ObjectType.DATE:
            self.obj = rpc_date_create(int(value.timestamp()))

        elif isinstance(value, (bytearray, bytes)) or force_type == ObjectType.BINARY:
            Py_INCREF(value)
            self.obj = rpc_data_create(<char *>value, <size_t>len(value), RPC_BINARY_DESTRUCTOR_ARG(destruct_bytes, <void *>value))

        elif isinstance(value, (RpcException, LibException)):
            extra = Object(value.extra)
            stack = Object(value.stacktrace)
            self.obj = rpc_error_create_with_stack(value.code, value.message.encode('utf-8'), extra.obj, stack.obj)

        elif isinstance(value, (list, tuple)) or force_type == ObjectType.ARRAY:
            self.obj = rpc_array_create()

            for v in value:
                child = Object(v)
                rpc_array_append_value(self.obj, child.obj)

        elif isinstance(value, dict) or force_type == ObjectType.DICTIONARY:
            self.obj = rpc_dictionary_create()

            for k, v in value.items():
                bkey = k.encode('utf-8')
                child = Object(v)
                rpc_dictionary_set_value(self.obj, bkey, child.obj)

        elif isinstance(value, uuid.UUID):
            bstr = str(value).encode('utf-8')
            self.obj = rpc_string_create(bstr)

        elif isinstance(value, Object):
            self.obj = rpc_copy((<Object>value).obj)

        elif hasattr(value, '__getstate__'):
            try:
                child = Object(value.__getstate__())
                self.obj = rpc_retain(child.obj)
            except:
                raise LibException(errno.EFAULT, "__getstate__() raised an exception")

        else:
            for typ, hook in type_hooks.items():
                if isinstance(value, typ):
                    try:
                        conv = hook(value)
                        if type(conv) is Object:
                            self.obj = rpc_copy((<Object>conv).obj)
                            break
                    except:
                        pass
            else:
                raise LibException(errno.EINVAL, "Unknown value type: {0}".format(type(value)))

        if typei:
            self.obj = rpct_newi((<TypeInstance>typei).rpctypei, self.obj)

    def __repr__(self):
        bdescr = rpc_copy_description(self.obj)
        result = bdescr.decode('utf-8')
        free(bdescr)
        return result

    def __str__(self):
        return str(self.value)

    def __bool__(self):
        return bool(self.value)

    def __int__(self):
        if self.type in (ObjectType.BOOL, ObjectType.UINT64, ObjectType.INT64, ObjectType.FD, ObjectType.DOUBLE):
            return int(self.value)

        raise TypeError('int() argument must be a number, bool or fd')

    def __float__(self):
        if self.type in (ObjectType.BOOL, ObjectType.UINT64, ObjectType.INT64, ObjectType.DOUBLE):
            return float(self.value)

        raise TypeError('float() argument must be a number or bool')

    def __dealloc__(self):
        if self.obj != <rpc_object_t>NULL:
            rpc_release(self.obj)

    @staticmethod
    cdef Object init_from_ptr(rpc_object_t ptr):
        cdef Object ret

        if ptr == <rpc_object_t>NULL:
            return None

        ret = Object.__new__(Object)
        ret.obj = ptr
        rpc_retain(ret.obj)
        return ret

    def unpack(self):
        """
        Unpack boxed value into a native Python value recursively.

        :param self:
        :return:
        """
        if self.typei and self.typei.type.clazz != TypeClass.BUILTIN:
            return self.typei.factory(self)

        if self.type == ObjectType.DICTIONARY:
            return {k: v.unpack() for k, v in self.value.items()}

        if self.type == ObjectType.ARRAY:
            return [i.unpack() for i in self.value]

        if self.type == ObjectType.FD:
            return self

        return self.value

    def validate(self):
        if not self.typei:
            raise LibException(errno.ENOENT, 'No type information')

        return self.typei.validate(self)

    property value:
        def __get__(self):
            cdef Array array
            cdef Dictionary dictionary
            cdef Object extra
            cdef Object stack
            cdef const char *c_string = NULL
            cdef const uint8_t *c_bytes = NULL
            cdef size_t c_len = 0

            if self.type == ObjectType.NIL:
                return None

            if self.type == ObjectType.BOOL:
                return rpc_bool_get_value(self.obj)

            if self.type == ObjectType.INT64:
                return rpc_int64_get_value(self.obj)

            if self.type == ObjectType.UINT64:
                return rpc_uint64_get_value(self.obj)

            if self.type == ObjectType.FD:
                return rpc_fd_get_value(self.obj)

            if self.type == ObjectType.STRING:
                c_string = rpc_string_get_string_ptr(self.obj)
                c_len = rpc_string_get_length(self.obj)
                return c_string[:c_len].decode('utf-8')

            if self.type == ObjectType.DOUBLE:
                return rpc_double_get_value(self.obj)

            if self.type == ObjectType.DATE:
                return datetime.datetime.utcfromtimestamp(rpc_date_get_value(self.obj))

            if self.type == ObjectType.BINARY:
                c_bytes = <uint8_t *>rpc_data_get_bytes_ptr(self.obj)
                c_len = rpc_data_get_length(self.obj)
                return <bytes>c_bytes[:c_len]

            if self.type == ObjectType.ERROR:
                extra = Object.__new__(Object)
                extra.obj = rpc_error_get_extra(self.obj)
                stack = Object.__new__(Object)
                stack.obj = rpc_error_get_stack(self.obj)

                return RpcException(
                    rpc_error_get_code(self.obj),
                    rpc_error_get_message(self.obj).decode('utf-8'),
                    extra,
                    stack
                )

            if self.type == ObjectType.ARRAY:
                array = Array.__new__(Array)
                array.obj = self.obj
                rpc_retain(array.obj)
                return array

            if self.type == ObjectType.DICTIONARY:
                dictionary = Dictionary.__new__(Dictionary)
                dictionary.obj = self.obj
                rpc_retain(dictionary.obj)
                return dictionary

    property type:
        def __get__(self):
            return ObjectType(rpc_get_type(self.obj))

    property typei:
        def __get__(self):
            return TypeInstance.init_from_ptr(rpct_get_typei(self.obj))


cdef class Array(Object):
    def __init__(self, value, force_type=None):
        if not isinstance(value, list):
            raise LibException(errno.EINVAL, "Cannot initialize array from {0} type".format(type(value)))

        super(Array, self).__init__(value, force_type)

    @staticmethod
    cdef bint c_applier(void *arg, size_t index, rpc_object_t value) with gil:
        cdef object cb = <object>arg
        cdef Object py_value

        py_value = Object.__new__(Object)
        py_value.obj = value

        rpc_retain(py_value.obj)

        return <bint>cb(index, py_value)

    def __applier(self, applier_f):
        rpc_array_apply(
            self.obj,
            RPC_ARRAY_APPLIER(
                <rpc_array_applier_f>Array.c_applier,
                <void *>applier_f,
            )
        )

    def append(self, value):
        cdef Object rpc_value

        if isinstance(value, Object):
            rpc_value = value
        else:
            rpc_value = Object(value)

        rpc_array_append_value(self.obj, rpc_value.obj)

    def extend(self, array):
        cdef Object rpc_value
        cdef Array rpc_array

        if isinstance(array, Array):
            rpc_array = array
        elif isinstance(array, list):
            rpc_array = Array(array)
        else:
            raise LibException(errno.EINVAL, "Array can be extended with only with list or another Array")

        for value in rpc_array:
            rpc_value = value
            rpc_array_append_value(self.obj, rpc_value.obj)

    def clear(self):
        rpc_release(self.obj)
        self.obj = rpc_array_create()

    def copy(self):
        cdef Array copy

        copy = Array.__new__(Array)
        with nogil:
            copy.obj = rpc_copy(self.obj)

        return copy

    def count(self, value):
        cdef Object v1
        cdef Object v2
        count = 0

        if isinstance(value, Object):
            v1 = value
        else:
            v1 = Object(value)

        def count_items(idx, v):
            nonlocal v2
            nonlocal count
            v2 = v

            if rpc_equal(v1.obj, v2.obj):
                count += 1

            return True

        self.__applier(count_items)

        return count

    def index(self, value):
        cdef Object v1
        cdef Object v2
        index = None

        if isinstance(value, Object):
            v1 = value
        else:
            v1 = Object(value)

        def find_index(idx, v):
            nonlocal v2
            nonlocal index
            v2 = v

            if rpc_equal(v1.obj, v2.obj):
                index = idx
                return False

            return True

        self.__applier(find_index)

        if index is None:
            raise LibException(errno.EINVAL, '{} is not in list'.format(value))

        return index

    def insert(self, index, value):
        cdef Object rpc_value

        if isinstance(value, Object):
            rpc_value = value
        else:
            rpc_value = Object(value)

        rpc_array_set_value(self.obj, index, rpc_value.obj)

    def pop(self, index=None):
        if index is None:
            index = self.__len__() - 1

        val = self.__getitem__(index)
        self.__delitem__(index)
        return val

    def remove(self, value):
        idx = self.index(value)
        self.__delitem__(idx)

    def __str__(self):
        return repr(self)

    def __contains__(self, value):
        try:
            self.index(value)
            return True
        except ValueError:
            return False

    def __delitem__(self, index):
        rpc_array_remove_index(self.obj, index)

    def __iter__(self):
        result = []
        def collect(idx, v):
            result.append(v)
            return True

        self.__applier(collect)

        for v in result:
            yield v

    def __len__(self):
        return rpc_array_get_count(self.obj)

    def __sizeof__(self):
        return rpc_array_get_count(self.obj)

    def __getitem__(self, index):
        cdef Object rpc_value

        rpc_value = Object.__new__(Object)
        rpc_value.obj = rpc_array_get_value(self.obj, index)
        if rpc_value.obj == <rpc_object_t>NULL:
            raise LibException(errno.ERANGE, 'Array index out of range')

        rpc_retain(rpc_value.obj)

        return rpc_value

    def __setitem__(self, index, value):
        cdef Object rpc_value

        rpc_value = Object(value)
        rpc_array_set_value(self.obj, index, rpc_value.obj)

        rpc_retain(rpc_value.obj)

    def __bool__(self):
        return len(self) > 0



cdef class Dictionary(Object):
    def __init__(self, value, force_type=None):
        if not isinstance(value, dict):
            raise LibException(errno.EINVAL, "Cannot initialize Dictionary RPC object from {type(value)} type")

        super(Dictionary, self).__init__(value, force_type)

    @staticmethod
    cdef bint c_applier(void *arg, char *key, rpc_object_t value) with gil:
        cdef object cb = <object>arg
        cdef Object py_value

        py_value = Object.__new__(Object)
        py_value.obj = value

        rpc_retain(py_value.obj)

        return <bint>cb(key.decode('utf-8'), py_value)

    def __applier(self, applier_f):
        rpc_dictionary_apply(
            self.obj,
            RPC_DICTIONARY_APPLIER(
                <rpc_dictionary_applier_f>Dictionary.c_applier,
                <void *>applier_f
            )
        )

    def clear(self):
        with nogil:
            rpc_release(self.obj)
            self.obj = rpc_dictionary_create()

    def copy(self):
        cdef Dictionary copy

        copy = Dictionary.__new__(Dictionary)
        with nogil:
            copy.obj = rpc_copy(self.obj)

        return copy

    def get(self, k, d=None):
        try:
            return self.__getitem__(k)
        except KeyError:
            return d

    def items(self):
        result = []
        def collect(k, v):
            result.append((k, v))
            return True

        self.__applier(collect)
        return result

    def keys(self):
        result = []
        def collect(k, v):
            result.append(k)
            return True

        self.__applier(collect)
        return result

    def pop(self, k, d=None):
        try:
            val = self.__getitem__(k)
            self.__delitem__(k)
            return val
        except KeyError:
            return d

    def setdefault(self, k, d=None):
        try:
            return self.__getitem__(k)
        except KeyError:
            self.__setitem__(k, d)
            return d

    def update(self, value):
        cdef Dictionary py_dict
        cdef Object py_value
        equal = False

        if isinstance(value, Dictionary):
            py_dict = value
        elif isinstance(value, dict):
            py_dict = Dictionary(value)
        else:
            raise LibException(errno.EINVAL, "Dictionary can be updated only with dict or other Dictionary object")

        for k, v in py_dict.items():
            py_value = v
            byte_key = k.encode('utf-8')
            rpc_dictionary_set_value(self.obj, byte_key, py_value.obj)

    def values(self):
        result = []
        def collect(k, v):
            result.append(v)
            return True

        self.__applier(collect)
        return result

    def __str__(self):
        return repr(self)

    def __contains__(self, value):
        cdef Object v1
        cdef Object v2
        equal = False

        if isinstance(value, Object):
            v1 = value
        else:
            v1 = Object(value)

        def compare(k, v):
            nonlocal v2
            nonlocal equal
            v2 = v

            if rpc_equal(v1.obj, v2.obj):
                equal = True
                return False
            return True

        self.__applier(compare)
        return equal

    def __delitem__(self, key):
        bytes_key = key.encode('utf-8')
        rpc_dictionary_remove_key(self.obj, bytes_key)

    def __iter__(self):
        keys = self.keys()
        for k in keys:
            yield k

    def __len__(self):
        return rpc_dictionary_get_count(self.obj)

    def __sizeof__(self):
        return rpc_dictionary_get_count(self.obj)

    def __getitem__(self, key):
        cdef Object rpc_value
        byte_key = key.encode('utf-8')

        rpc_value = Object.__new__(Object)
        rpc_value.obj = rpc_dictionary_get_value(self.obj, byte_key)
        if rpc_value.obj == <rpc_object_t>NULL:
            raise LibException(errno.EINVAL, 'Key {} does not exist'.format(key))

        rpc_retain(rpc_value.obj)

        return rpc_value

    def __setitem__(self, key, value):
        cdef Object rpc_value
        byte_key = key.encode('utf-8')

        rpc_value = Object(value)
        rpc_dictionary_set_value(self.obj, byte_key, rpc_value.obj)

        rpc_retain(rpc_value.obj)

    def __bool__(self):
        return len(self) > 0


cdef raise_internal_exc(rpc=False):
    cdef rpc_object_t error

    error = rpc_get_last_error()
    exc = LibException

    if rpc:
        exc = RpcException

    if error != <rpc_object_t>NULL:
        raise exc(rpc_error_get_code(error), rpc_error_get_message(error).decode('utf-8'))

    raise exc(errno.EFAULT, "Unknown error")


cdef void destruct_bytes(void *arg, void *buffer) with gil:
    cdef object value = <object>arg
    Py_DECREF(value)


def uint(value):
    return Object(value, force_type=ObjectType.UINT64)


def fd(value):
    return Object(value, force_type=ObjectType.FD)


def unpack(fn):
    fn.__librpc_unpack__ = True
    return fn