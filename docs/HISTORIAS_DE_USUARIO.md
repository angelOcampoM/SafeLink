# SafeLink — Historias de usuario

Servicio de respuesta de seguridad privada bajo demanda
Desarrollo para Dispositivos Inteligentes — UTEZ

> Las historias corresponden únicamente a los tres roles funcionales del sistema: usuario protegido, guardia de respuesta y administrador. La aplicación se desarrolla en **Flutter** y las pruebas se enfocan principalmente en la interfaz.

**Leyenda:** `[x]` criterio cumplido y cubierto por pruebas · `[ ]` pendiente.
Los pendientes marcados *(Sprint 3 · sensores)* necesitan cámara, GPS, brújula o
acelerómetro reales: no se pueden cerrar mientras el prototipo trabaje con datos
simulados, y no bloquean la entrega del front.

**Estado del rol usuario protegido** (rama `feat/S2-design-system`, 30/10/2026):
37 de 46 criterios cumplidos. Los 9 pendientes dependen de sensores.
Las secciones de guardia y administrador aún no se han verificado contra el código.

---

## Usuario protegido

### U-01 · Registro de cuenta
**Como** usuario protegido, **quiero** registrarme por mi cuenta en la aplicación, **para** poder solicitar el servicio cuando me encuentre en riesgo.

**Depende de:** ninguna historia.

**Criterios de aceptación**
- [x] El formulario solicita nombre, correo, teléfono y contraseña.
- [x] Los campos obligatorios se validan antes de enviar el formulario y los errores se muestran junto al campo correspondiente.
- [x] No se permite registrar una cuenta con un correo ya existente.
- [x] La cuenta creada tiene asignado el rol de usuario protegido.
- [x] Al terminar el registro, el usuario accede a la pantalla principal, después de la explicación de permisos de U-02.

### U-02 · Inicio de sesión
**Como** usuario protegido, **quiero** iniciar sesión con mis credenciales, **para** acceder directamente al botón de alerta.

**Depende de:** U-01 (la cuenta debe existir).

**Criterios de aceptación**
- [x] Con credenciales válidas, el usuario entra directamente a la pantalla del botón de alerta.
- [x] Con credenciales inválidas se muestra un mensaje de error sin indicar qué dato es incorrecto.
- [x] La sesión permanece activa al cerrar y volver a abrir la aplicación, hasta que el usuario cierre sesión.
- [x] Al iniciar sesión por primera vez, la aplicación solicita los permisos de cámara, ubicación y notificaciones, explicando para qué se usa cada uno.
- [x] La explicación de permisos puede volver a consultarse desde Configuración.

### U-03 · Disparo de alerta por toque simple
**Como** usuario protegido, **quiero** que al tocar el botón aparezca una cuenta regresiva para cancelar, **para** evitar enviar una alerta por un toque accidental.

**Depende de:** U-02 (sesión iniciada y botón de alerta), U-06 (captura de evidencia al disparar), U-07 (envío de ubicación una vez disparada).

**Criterios de aceptación**
- [x] Al tocar el botón aparece una cuenta regresiva visible de 3 segundos.
- [x] Durante la cuenta regresiva se muestra un botón de "Cancelar" claramente identificable.
- [x] Si el usuario cancela, la alerta no se envía y la pantalla vuelve a su estado inicial.
- [x] Si la cuenta regresiva termina sin cancelación, la alerta se dispara.
- [x] La alerta queda registrada con el método de disparo "toque".

### U-04 · Disparo de alerta por mantener presionado
**Como** usuario protegido, **quiero** mantener presionado el botón mientras decido si enviar la alerta, **para** dispararla al soltarlo o descartarla si ya no la necesito.

**Depende de:** U-02 (sesión iniciada y botón de alerta), U-06 (captura de evidencia al disparar), U-07 (envío de ubicación una vez disparada).

**Criterios de aceptación**
- [x] Al mantener presionado el botón, este cambia visualmente para indicar que la alerta está en espera.
- [x] Mientras el botón está presionado aparece una zona de "Descartar" en pantalla, similar a un bote de basura.
- [x] Si el usuario suelta el botón fuera de la zona de descarte, la alerta se dispara de inmediato.
- [x] Si el usuario arrastra el botón hasta la zona de descarte y lo suelta ahí, la alerta se descarta y no se envía.
- [x] La zona de descarte cambia visualmente cuando el botón se encuentra sobre ella.
- [x] El tiempo que el usuario mantiene presionado el botón no tiene límite.
- [x] La alerta queda registrada con el método de disparo "mantener presionado".

### U-05 · Disparo de alerta sin desbloquear el teléfono
**Como** usuario protegido, **quiero** disparar la alerta agitando el teléfono, **para** pedir ayuda cuando no puedo desbloquear la pantalla.

**Depende de:** U-02 (sesión iniciada), U-06 (captura de evidencia al disparar), U-07 (envío de ubicación una vez disparada).

> **Corrección del 30/10/2026.** Esta historia pedía "doble clic del botón de bajar
> volumen". Se cambió a **agitación** porque contradecía a G-03 de este mismo
> documento ("las alertas disparadas por agitación se marcan como urgentes") y a la
> sección 9 del documento de metodología, que declara el **acelerómetro** como sensor
> del que depende el proceso. El código ya implementa agitación. Pendiente de
> ratificación del Product Owner.

**Criterios de aceptación**
- [x] El usuario puede activar o desactivar esta función desde la configuración.
- [x] La alerta por agitación se envía de inmediato, sin cuenta regresiva: es el método para cuando no hay tiempo de confirmar.
- [x] La alerta queda registrada con el método de disparo "agitación" y el guardia la ve marcada como urgente (ver G-03).
- [ ] *(Sprint 3 · sensores)* La aplicación detecta la agitación del dispositivo con el acelerómetro, incluso con la pantalla bloqueada.
- [ ] *(Sprint 3 · sensores)* La detección funciona mediante un servicio en segundo plano que se mantiene activo con una notificación persistente.
- [ ] *(Sprint 3 · sensores)* Un movimiento normal del teléfono, como caminar o sacarlo del bolsillo, no dispara la alerta.
- [ ] *(Sprint 3 · sensores)* Al detectarse la agitación, el teléfono vibra para confirmar que la alerta fue enviada.

### U-06 · Captura automática de evidencia
**Como** usuario protegido, **quiero** que la aplicación capture la evidencia de forma automática al disparar la alerta, **para** que el guardia tenga contexto sin que yo tenga que hacer nada más.

**Depende de:** U-02 (permisos de cámara y ubicación). Se ejecuta al completarse U-03, U-04 o U-05.

**Criterios de aceptación**
- [ ] *(Sprint 3 · sensores)* Al dispararse la alerta se toma una sola fotografía del entorno, sin intervención del usuario.
- [ ] *(Sprint 3 · sensores)* Junto con la fotografía se registran la ubicación GPS, el rumbo de la cámara respecto al norte, la marca de tiempo y el método de disparo. *La alerta ya viaja con los cuatro campos; hoy la foto, la ubicación y el rumbo llevan valores simulados.*
- [ ] *(Sprint 3 · sensores)* Los datos de ubicación, rumbo y hora provienen de los sensores en el instante del disparo, no de los metadatos del archivo.
- [x] Si la fotografía no se genera, la alerta se envía de todas formas y se marca como evidencia incompleta.
- [x] Si no hay coordenadas válidas, la alerta no se publica y queda en estado pendiente de ubicación, informando al usuario en pantalla.

### U-07 · Envío de ubicación en tiempo real
**Como** usuario protegido, **quiero** que mi ubicación se envíe en tiempo real mientras la alerta está activa, **para** que el guardia me encuentre aunque me desplace.

**Depende de:** U-02 (permiso de ubicación), U-06 (la alerta debe estar registrada con su ubicación inicial). Se inicia con U-03, U-04 o U-05 y se detiene con U-09.

**Criterios de aceptación**
- [ ] *(Sprint 3 · sensores)* La ubicación se transmite de forma continua desde que se dispara la alerta, sin importar el método de disparo.
- [ ] *(Sprint 3 · sensores)* La transmisión continúa aunque la aplicación esté en segundo plano o la pantalla bloqueada.
- [x] Se muestra un indicador visible de que la ubicación se está compartiendo.
- [x] La transmisión se detiene cuando la alerta se cierra.

### U-08 · Guardia asignado y tiempo estimado
**Como** usuario protegido, **quiero** saber qué guardia me atenderá y en cuánto tiempo llegará, **para** tener certeza de que la ayuda va en camino.

**Depende de:** U-06 (alerta registrada), U-07 (ubicación del usuario), G-05 (aceptación de la alerta por el guardia).

**Criterios de aceptación**
- [x] Mientras ningún guardia acepta la alerta, se muestra el estado "Buscando guardia".
- [x] Cuando un guardia acepta, se muestran su nombre y el tiempo estimado de llegada.
- [x] El tiempo estimado se actualiza conforme el guardia se acerca.
- [x] El usuario no puede ver la ubicación del guardia en el mapa.

### U-09 · Confirmación de atención
**Como** usuario protegido, **quiero** confirmar que ya fui atendido, **para** cerrar la alerta.

**Depende de:** U-08 (guardia asignado), G-07 (registro de llegada del guardia), A-04 (bandeja de alertas escaladas, para el escalamiento por falta de confirmación).

**Criterios de aceptación**
- [x] La opción "Ya fui atendido" se habilita una vez que el guardia marca su llegada.
- [x] Al confirmar, la alerta se cierra y la pantalla vuelve al botón de alerta.
- [x] El usuario no puede cerrar una alerta que ningún guardia aceptó; esta se archiva como sin respuesta.
- [x] Si el usuario no confirma dentro del tiempo definido, la alerta escala a la bandeja del administrador.

---

## Guardia de respuesta

### G-01 · Inicio de sesión
**Como** guardia de respuesta, **quiero** iniciar sesión con la cuenta que me asignó el administrador, **para** acceder a las alertas de mi zona.

**Criterios de aceptación**
- [ ] La aplicación no ofrece registro para guardias; solo pueden ingresar con una cuenta creada por el administrador.
- [ ] Con credenciales válidas, el guardia entra a su listado de alertas.
- [ ] Un guardia dado de baja no puede iniciar sesión.
- [ ] Al iniciar sesión por primera vez, la aplicación solicita los permisos de ubicación y notificaciones.

### G-02 · Recepción de alertas
**Como** guardia de respuesta, **quiero** recibir una notificación cada vez que se genera una alerta en mi zona, **para** enterarme de inmediato aunque no esté usando la aplicación.

**Criterios de aceptación**
- [ ] El guardia recibe una notificación por cada alerta nueva dentro de su radio, con la aplicación cerrada o en segundo plano.
- [ ] Al tocar la notificación se abre el detalle de la alerta.
- [ ] **En Android**, la notificación suena aunque el teléfono esté en silencio o en modo No molestar, mediante un canal de notificación de tipo alarma y una notificación de pantalla completa.
- [ ] **En iOS**, el guardia recibe la notificación de forma normal; no se contempla la recepción en modo silencio o No molestar, ya que requiere un permiso especial de Apple.

### G-03 · Listado de alertas por cercanía y prioridad
**Como** guardia de respuesta, **quiero** ver las alertas activas ordenadas por cercanía y prioridad, **para** decidir cuál atender primero.

**Criterios de aceptación**
- [ ] Solo se muestran alertas dentro del radio de cobertura del guardia y durante su turno.
- [ ] Las alertas se ordenan combinando la distancia y la prioridad.
- [ ] La prioridad aumenta conforme crece el tiempo de espera de la alerta sin ser aceptada.
- [ ] Las alertas disparadas por agitación se marcan como urgentes y aparecen destacadas.
- [ ] Cada alerta muestra la distancia, el tiempo de espera y el método de disparo.
- [ ] Las alertas con evidencia incompleta aparecen señaladas.
- [ ] Las alertas aceptadas por otro guardia desaparecen del listado.

### G-04 · Detalle de la alerta
**Como** guardia de respuesta, **quiero** consultar el detalle de una alerta, **para** conocer el contexto antes de aceptarla.

**Criterios de aceptación**
- [ ] El detalle muestra la fotografía del entorno, la ubicación en el mapa, el rumbo y el método de disparo.
- [ ] La fotografía se muestra orientada en el mapa según el rumbo registrado.
- [ ] La fotografía puede ampliarse a pantalla completa.
- [ ] Si la evidencia está incompleta, se indica claramente qué dato falta.

### G-05 · Aceptación de alerta
**Como** guardia de respuesta, **quiero** aceptar una alerta, **para** indicar que la estoy atendiendo.

**Criterios de aceptación**
- [ ] Desde el detalle, el guardia puede aceptar la alerta con un botón.
- [ ] Al aceptarla, la alerta queda asignada al guardia y cambia a estado "En atención".
- [ ] La alerta desaparece del listado de los demás guardias.
- [ ] Si otro guardia la aceptó primero, se muestra un aviso y la alerta deja de estar disponible.
- [ ] El guardia no puede cerrar la alerta por su cuenta.

### G-06 · Ruta hacia el usuario
**Como** guardia de respuesta, **quiero** ver la ruta hacia el usuario en un mapa, **para** llegar a él aunque se siga moviendo.

**Criterios de aceptación**
- [ ] Al aceptar la alerta, se muestra un mapa con la ubicación del guardia, la del usuario y la ruta entre ambos.
- [ ] La posición del usuario y la ruta se actualizan conforme el usuario se desplaza.
- [ ] Se muestran la distancia restante y el tiempo estimado de llegada.
- [ ] El guardia puede abrir la ruta en una aplicación de navegación externa, como Google Maps.
- [ ] La actualización se detiene cuando la alerta se cierra.

### G-07 · Registro de llegada
**Como** guardia de respuesta, **quiero** marcar mi llegada al punto, **para** registrar que me presenté a atender la alerta.

**Criterios de aceptación**
- [ ] El botón "Llegué" solo se habilita cuando el guardia se encuentra dentro del radio de la geocerca.
- [ ] Fuera de la geocerca, el botón permanece deshabilitado e indica la distancia restante.
- [ ] Al marcar la llegada, se registra la hora y se notifica al usuario.

---

## Administrador

### A-01 · Alta de guardias
**Como** administrador, **quiero** dar de alta a los guardias, **para** que solo personal autorizado opere en el sistema.

**Criterios de aceptación**
- [ ] El formulario solicita nombre, correo, teléfono y una contraseña inicial.
- [ ] Los campos obligatorios se validan antes de guardar.
- [ ] No se permite registrar un guardia con un correo ya existente.
- [ ] El guardia creado aparece en el listado de guardias.

### A-02 · Edición y baja de guardias
**Como** administrador, **quiero** editar los datos de los guardias y darlos de baja, **para** mantener actualizado al personal disponible.

**Criterios de aceptación**
- [ ] El listado de guardias permite buscar por nombre.
- [ ] El administrador puede editar los datos de un guardia.
- [ ] Dar de baja a un guardia solicita confirmación antes de aplicarse.
- [ ] Un guardia dado de baja no puede iniciar sesión ni recibe alertas.
- [ ] Las alertas atendidas por un guardia dado de baja se conservan en el historial.

### A-03 · Asignación de turnos y radios de cobertura
**Como** administrador, **quiero** asignar turnos y radios de cobertura a los guardias, **para** controlar quién recibe alertas y en qué zona.

**Criterios de aceptación**
- [ ] El administrador asigna a cada guardia un horario de turno.
- [ ] El administrador define el radio de cobertura y puede visualizarlo en un mapa.
- [ ] Un guardia solo recibe alertas si tiene un turno vigente y un radio definido.
- [ ] El listado de guardias indica quiénes se encuentran en turno.

### A-04 · Bandeja de alertas escaladas
**Como** administrador, **quiero** una bandeja con las alertas escaladas, **para** revisar y resolver los casos que no se cerraron correctamente.

**Criterios de aceptación**
- [ ] Las alertas que ningún guardia aceptó llegan automáticamente a la bandeja.
- [ ] Las alertas sin confirmación de cierre por parte del usuario llegan automáticamente a la bandeja.
- [ ] Cada alerta indica el motivo por el que fue escalada.
- [ ] El administrador puede consultar el detalle completo de la alerta, incluida la evidencia.
- [ ] El administrador puede marcar la alerta como resuelta, como falsa alarma o como incidencia de servicio.

### A-05 · Historial de alertas
**Como** administrador, **quiero** consultar el historial de alertas, **para** auditar el servicio prestado.

**Criterios de aceptación**
- [ ] El historial muestra cada alerta con su fecha, usuario, guardia asignado, método de disparo y estado final.
- [ ] El historial puede filtrarse por fecha, guardia, usuario y estado.
- [ ] Al seleccionar una alerta se muestra su detalle completo: evidencia, hora de aceptación, hora de llegada y hora de cierre.

### A-06 · Métricas generales del servicio
**Como** administrador, **quiero** consultar métricas generales del servicio, **para** evaluar el desempeño de la atención.

**Criterios de aceptación**
- [ ] El panel muestra el tiempo promedio de aceptación de las alertas.
- [ ] El panel muestra el tiempo promedio de llegada de los guardias.
- [ ] El panel muestra el porcentaje de alertas sin respuesta y el porcentaje de cierres confirmados.
- [ ] El panel muestra la distribución de alertas por horario y por zona.
- [ ] Las métricas pueden filtrarse por rango de fechas.

### A-07 · Métricas por guardia
**Como** administrador, **quiero** consultar las métricas de cada guardia, **para** evaluar su desempeño individual.

**Criterios de aceptación**
- [ ] Por cada guardia se muestran las alertas atendidas.
- [ ] Por cada guardia se muestran el tiempo promedio de aceptación y el tiempo promedio de llegada.
- [ ] Por cada guardia se muestran las alertas escaladas.
- [ ] Las métricas pueden filtrarse por rango de fechas.

### A-08 · Bloqueo por falsas alarmas
**Como** administrador, **quiero** que se bloquee temporalmente a los usuarios con falsas alarmas reiteradas, **para** evitar el mal uso del servicio.

**Criterios de aceptación**
- [ ] El sistema lleva un conteo de falsas alarmas por usuario, a partir de las alertas marcadas como tales en la bandeja.
- [ ] Al alcanzar el número definido de falsas alarmas, el usuario queda bloqueado temporalmente.
- [ ] El usuario bloqueado ve un aviso en lugar del botón de alerta, con la fecha en que termina el bloqueo.
- [ ] El administrador puede consultar a los usuarios bloqueados y retirar el bloqueo de forma manual.
