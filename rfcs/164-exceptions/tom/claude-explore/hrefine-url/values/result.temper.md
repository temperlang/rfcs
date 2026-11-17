# A result type, written as user code

Design A's "failure with a reason", as any library can write it today:
a sealed interface with a success class and a failure class. Both
classes carry both type parameters, since a `Failed` has to be a
`Result<T, E>` for whatever `T` its function returns; so passing a
failure up to a function with a different `T` makes a new `Failed`.
Under design A this type would be built in (or in std), with a
propagation operator and a representation chosen per backend.

    export sealed interface Result<@out T, @out E> {}

    export class Ok<@out T, @out E>(public value: T) extends Result<T, E> {}

    export class Failed<@out T, @out E>(public error: E) extends Result<T, E> {}
